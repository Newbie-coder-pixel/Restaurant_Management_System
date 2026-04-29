import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/qr_order_model.dart';
import '../providers/qr_cart_provider.dart';

class QrOrderRepository {
  final SupabaseClient _client;

  QrOrderRepository(this._client);

  // ─── Create Order ──────────────────────────────────────────────────────────
  Future<QrOrderModel> createOrder({
    required QrOrderSession session,
    required String branchId,
    String? notes,
  }) async {
    final queueNumber = await _generateQueueNumber(branchId);

    try {
      debugPrint('🔄 Membuat QR Order: $queueNumber | Items: ${session.items.length}');

      // 1. Insert orders
      final orderResponse = await _client
          .from('orders')
          .insert({
            'queue_number': queueNumber,
            'order_number': queueNumber,
            'table_id': session.tableId,
            'table_name': session.tableName ?? 'Meja ${session.tableId}',
            'customer_name': session.customerName ?? 'Tamu',
            'total_amount': session.totalAmount,
            'status': 'created',
            'payment_status': 'pending',
            'payment_method': session.paymentMethod?.name.toLowerCase() ?? 'kasir',
            'branch_id': branchId,
            'order_type': 'qr_order',
            'source': 'dine_in',
            if (notes != null && notes.isNotEmpty) 'notes': notes,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final String orderId = orderResponse['id'] as String;

      // 2. Insert order_items — subtotal TIDAK di-insert (GENERATED column)
      if (session.items.isNotEmpty) {
        final orderItemsData = session.items.map((cartItem) {
          final itemData = <String, dynamic>{
            'order_id': orderId,
            'menu_item_id': cartItem.menuItem.id,
            'menu_item_name': cartItem.menuItem.name,
            'unit_price': cartItem.menuItem.price,
            'quantity': cartItem.quantity,
          };
          if (cartItem.notes != null && cartItem.notes!.isNotEmpty) {
            itemData['special_requests'] = cartItem.notes;
          }
          return itemData;
        }).toList();

        await _client.from('order_items').insert(orderItemsData);
        debugPrint('✅ ${orderItemsData.length} items tersimpan');
      }

      // 3. Update status meja SEGERA setelah insert
      if (session.tableId.isNotEmpty) {
        try {
          debugPrint('🔍 tableId yang akan diupdate: "${session.tableId}"');

          // Cek dulu apakah meja ada dan status saat ini
          final checkResult = await _client
              .from('restaurant_tables')
              .select('id, status')
              .eq('id', session.tableId)
              .maybeSingle();
          debugPrint('🔍 Meja ditemukan: $checkResult');

          if (checkResult != null) {
            // ✅ FIX: hapus .select() dari update — ini penyebab return []
            await _client
                .from('restaurant_tables')
                .update({
                  'status': 'occupied',
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', session.tableId);
            debugPrint('✅ Update selesai');

            // Verifikasi dengan query terpisah
            final verify = await _client
                .from('restaurant_tables')
                .select('id, status')
                .eq('id', session.tableId)
                .maybeSingle();
            debugPrint('✅ Status meja setelah update: ${verify?['status']}');
          } else {
            debugPrint('⚠️ Meja tidak ditemukan dengan id: ${session.tableId}');
          }
        } catch (e) {
          debugPrint('⚠️ Gagal update status meja: $e');
        }
      } else {
        debugPrint('⚠️ tableId kosong, skip update meja');
      }

      // 4. Fetch ulang order beserta items
      await Future.delayed(const Duration(milliseconds: 500));
      QrOrderModel? fullOrder = await fetchOrder(orderId);

      if (fullOrder != null) {
        debugPrint('✅ Order dibuat: ${fullOrder.items.length} items, total ${fullOrder.totalAmount}');
        return fullOrder;
      }

      // Fallback jika fetch gagal
      return QrOrderModel.fromMap(_normalizeOrderMap(orderResponse, const []));

    } catch (e, stack) {
      debugPrint('❌ Gagal create order: $e\n$stack');
      rethrow;
    }
  }

  // ── Watch Order realtime ───────────────────────────────────────────────────
  Stream<QrOrderModel> watchOrder(String orderId) {
    late StreamController<QrOrderModel> controller;
    RealtimeChannel? channel;

    Future<void> fetchAndEmit() async {
      try {
        final order = await fetchOrder(orderId);
        if (order != null && !controller.isClosed) controller.add(order);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    controller = StreamController<QrOrderModel>(
      onListen: () async {
        await fetchAndEmit();
        channel = _client
            .channel('order_watch_$orderId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'orders',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: orderId,
              ),
              callback: (_) => fetchAndEmit(),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'order_items',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'order_id',
                value: orderId,
              ),
              callback: (_) => fetchAndEmit(),
            )
            .subscribe();
      },
      onCancel: () {
        channel?.unsubscribe();
        controller.close();
      },
    );

    return controller.stream;
  }

  // ── Fetch order + items (DUA QUERY TERPISAH) ─────────────────────────────
  Future<QrOrderModel?> fetchOrder(String orderId) async {
    final orderResp = await _client
        .from('orders')
        .select(
          'id, order_number, queue_number, table_id, table_name, '
          'customer_name, total_amount, status, payment_status, '
          'payment_method, created_at, updated_at, branch_id, notes',
        )
        .eq('id', orderId)
        .maybeSingle();
    if (orderResp == null) return null;

    final itemsResp = await _client
        .from('order_items')
        .select('id, menu_item_id, menu_item_name, unit_price, quantity, subtotal, special_requests')
        .eq('order_id', orderId);

    debugPrint('📦 fetchOrder items: ${itemsResp.length}');

    final normalized = _normalizeOrderMap(orderResp, itemsResp);
    return QrOrderModel.fromMap(normalized);
  }

  Future<QrOrderModel?> fetchByQueueNumber(String queueNumber) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final orderResp = await _client
        .from('orders')
        .select(
          'id, order_number, queue_number, table_id, table_name, '
          'customer_name, total_amount, status, payment_status, '
          'payment_method, created_at, updated_at, branch_id, notes',
        )
        .eq('queue_number', queueNumber)
        .gte('created_at', startOfDay.toIso8601String())
        .maybeSingle();
    if (orderResp == null) return null;

    final itemsResp = await _client
        .from('order_items')
        .select('id, menu_item_id, menu_item_name, unit_price, quantity, subtotal, special_requests')
        .eq('order_id', orderResp['id'] as String);

    return QrOrderModel.fromMap(_normalizeOrderMap(orderResp, itemsResp));
  }

  // ── Normalize ─────────────────────────────────────────────────────────────
  Map<String, dynamic> _normalizeOrderMap(
    Map<String, dynamic> order,
    List<dynamic> rawItems,
  ) {
    final orderItems = rawItems.map((e) {
      final item = Map<String, dynamic>.from(e as Map);
      item['price'] = item['unit_price'] ?? item['price'];
      item['notes'] = item['special_requests'] ?? item['notes'];
      return item;
    }).toList();

    return {
      ...order,
      'items': orderItems,
    };
  }

  Future<List<Map<String, dynamic>>> fetchMenuByBranch(String branchId) async {
    if (branchId.trim().isEmpty) return [];
    try {
      final items = await _client
          .from('menu_items')
          .select('''
            id, branch_id, category_id, name, description, price,
            image_url, is_available, is_seasonal, preparation_time_minutes,
            sort_order, created_at, updated_at,
            menu_categories!inner(id, name, sort_order)
          ''')
          .eq('branch_id', branchId)
          .eq('is_available', true)
          .order('sort_order', ascending: true);
      return List<Map<String, dynamic>>.from(items);
    } catch (e, stack) {
      debugPrint('❌ ERROR fetchMenuByBranch: $e\n$stack');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> fetchTableInfo(String tableId) async {
    try {
      final row = await _client
          .from('restaurant_tables')
          .select('*, branches(id, name)')
          .eq('id', tableId)
          .maybeSingle();
      return row;
    } catch (e) {
      final row = await _client
          .from('restaurant_tables')
          .select('*')
          .eq('id', tableId)
          .maybeSingle();
      return row != null ? {...row, 'branches': null} : null;
    }
  }

  Future<String> _generateQueueNumber(String branchId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    try {
      final rows = await _client
          .from('orders')
          .select('queue_number')
          .eq('branch_id', branchId)
          .gte('created_at', startOfDay.toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);

      if (rows.isEmpty) return 'A001';
      final lastQueue = rows.first['queue_number'] as String;
      final letter = lastQueue[0];
      final number = int.tryParse(lastQueue.substring(1)) ?? 0;
      if (number < 999) return '$letter${(number + 1).toString().padLeft(3, '0')}';
      return '${String.fromCharCode(letter.codeUnitAt(0) + 1)}001';
    } catch (_) {
      return 'A${(Random().nextInt(999) + 1).toString().padLeft(3, '0')}';
    }
  }
}

final qrOrderRepositoryProvider = Provider<QrOrderRepository>((ref) {
  return QrOrderRepository(Supabase.instance.client);
});

class QrOrderCreationNotifier extends StateNotifier<AsyncValue<QrOrderModel?>> {
  final QrOrderRepository _repo;
  QrOrderCreationNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<QrOrderModel?> submit({
    required QrOrderSession session,
    required String branchId,
    String? notes,
  }) async {
    state = const AsyncValue.loading();
    try {
      final order = await _repo.createOrder(session: session, branchId: branchId, notes: notes);
      state = AsyncValue.data(order);
      return order;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  void reset() => state = const AsyncValue.data(null);
}

final qrOrderCreationProvider =
    StateNotifierProvider<QrOrderCreationNotifier, AsyncValue<QrOrderModel?>>(
  (ref) => QrOrderCreationNotifier(ref.read(qrOrderRepositoryProvider)),
);

final qrOrderWatchProvider =
    StreamProvider.family<QrOrderModel, String>((ref, orderId) {
  return ref.read(qrOrderRepositoryProvider).watchOrder(orderId);
});