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
    String? notes, // ✅ FIX: tambah parameter notes
  }) async {
    final queueNumber = await _generateQueueNumber(branchId);

    try {
      debugPrint('🔄 Membuat QR Order: $queueNumber | Table: ${session.tableId} | Items: ${session.items.length}');

      // 1. Insert ke tabel orders
      final orderData = {
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
        'source': 'dine_in', // ✅ FIX: pakai dine_in bukan dineIn
        if (notes != null && notes.isNotEmpty) 'notes': notes, // ✅ FIX: simpan notes
        'created_at': DateTime.now().toIso8601String(),
      };

      final orderResponse = await _client
          .from('orders')
          .insert(orderData)
          .select()
          .single();

      final String orderId = orderResponse['id'] as String;

      // 2. Insert ke tabel order_items
      // ✅ FIX: subtotal DIHAPUS karena GENERATED column di DB
      if (session.items.isNotEmpty) {
        final orderItemsData = session.items.map((cartItem) {
          final itemData = <String, dynamic>{
            'order_id': orderId,
            'menu_item_id': cartItem.menuItem.id,
            'menu_item_name': cartItem.menuItem.name,
            'unit_price': cartItem.menuItem.price,
            'quantity': cartItem.quantity,
            // subtotal tidak di-insert → dihitung otomatis oleh DB
          };
          // ✅ FIX: simpan notes per item (special_requests)
          if (cartItem.notes != null && cartItem.notes!.isNotEmpty) {
            itemData['special_requests'] = cartItem.notes;
          }
          return itemData;
        }).toList();

        await _client.from('order_items').insert(orderItemsData);

        debugPrint('✅ Berhasil menyimpan ${orderItemsData.length} item ke tabel order_items');
      }

      debugPrint('✅ Order berhasil dibuat! ID: $orderId | Queue: $queueNumber');

      return QrOrderModel.fromMap(orderResponse);
    } catch (e, stack) {
      debugPrint('❌ Gagal create order: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  // ── Watch Order (realtime) ─────────────────────────────────────────────────
  Stream<QrOrderModel> watchOrder(String orderId) {
    late StreamController<QrOrderModel> controller;
    RealtimeChannel? channel;

    Future<void> fetchAndEmit() async {
      try {
        final order = await fetchOrder(orderId);
        if (order != null && !controller.isClosed) {
          controller.add(order);
        }
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

  // ── Fetch Order (dengan items) ─────────────────────────────────────────────
  Future<QrOrderModel?> fetchOrder(String orderId) async {
    final response = await _client
        .from('orders')
        .select('*, order_items(*)')
        .eq('id', orderId)
        .maybeSingle();
    if (response == null) return null;
    return QrOrderModel.fromMap(_normalizeOrderMap(response));
  }

  Future<QrOrderModel?> fetchByQueueNumber(String queueNumber) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final response = await _client
        .from('orders')
        .select('*, order_items(*)')
        .eq('queue_number', queueNumber)
        .gte('created_at', startOfDay.toIso8601String())
        .maybeSingle();
    if (response == null) return null;
    return QrOrderModel.fromMap(_normalizeOrderMap(response));
  }

  // ── Normalize map ──────────────────────────────────────────────────────────
  Map<String, dynamic> _normalizeOrderMap(Map<String, dynamic> raw) {
    final orderItems = (raw['order_items'] as List<dynamic>? ?? [])
        .map((e) {
          final item = Map<String, dynamic>.from(e as Map);
          if (!item.containsKey('price') && item.containsKey('unit_price')) {
            item['price'] = item['unit_price'];
          }
          if (!item.containsKey('notes') && item.containsKey('special_requests')) {
            item['notes'] = item['special_requests'];
          }
          return item;
        })
        .toList();

    return {
      ...raw,
      'items': orderItems,
    };
  }

  Future<List<Map<String, dynamic>>> fetchMenuByBranch(String branchId) async {
    if (branchId.trim().isEmpty) {
      debugPrint('❌ fetchMenuByBranch: branchId kosong!');
      return [];
    }

    try {
      debugPrint('🔄 Fetching menu for branch: $branchId');

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

      debugPrint('✅ Berhasil fetch ${items.length} menu items');
      return List<Map<String, dynamic>>.from(items);
    } catch (e, stack) {
      debugPrint('❌ ERROR di fetchMenuByBranch: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> fetchTableInfo(String tableId) async {
    try {
      final tableRow = await _client
          .from('restaurant_tables')
          .select('*, branches(id, name)')
          .eq('id', tableId)
          .maybeSingle();

      if (tableRow == null) {
        debugPrint('⚠️ Table dengan ID $tableId tidak ditemukan');
        return null;
      }
      debugPrint('✅ Table info ditemukan: ${tableRow['table_number']}');
      return tableRow;
    } catch (e) {
      debugPrint('❌ ERROR fetchTableInfo: $e');
      final tableRow = await _client
          .from('restaurant_tables')
          .select('*')
          .eq('id', tableId)
          .maybeSingle();
      if (tableRow != null) {
        return {...tableRow, 'branches': null};
      }
      return null;
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

      if (number < 999) {
        return '$letter${(number + 1).toString().padLeft(3, '0')}';
      } else {
        final nextLetter = String.fromCharCode(letter.codeUnitAt(0) + 1);
        return '${nextLetter}001';
      }
    } catch (_) {
      final rnd = Random().nextInt(999) + 1;
      return 'A${rnd.toString().padLeft(3, '0')}';
    }
  }
}

// ── Providers ──────────────────────────────────────────────────────────────────
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
      final order = await _repo.createOrder(
        session: session,
        branchId: branchId,
        notes: notes,
      );
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
  final repo = ref.read(qrOrderRepositoryProvider);
  return repo.watchOrder(orderId);
});