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
      debugPrint('🔄 Creating QR Order: $queueNumber | Items: ${session.items.length}');

      // 1. Insert orders
      final orderResponse = await _client
          .from('orders')
          .insert({
            'queue_number': queueNumber,
            'order_number': queueNumber,
            'table_id': session.tableId,
            'table_name': session.tableName ?? 'Table ${session.tableId}',
            'customer_name': session.customerName ?? 'Guest',
            if (session.customerPhone != null && session.customerPhone!.isNotEmpty) 'customer_phone': session.customerPhone,
            'customer_email': session.customerEmail ?? '',
            'subtotal': session.subtotal,
            'tax_amount': session.pb1Amount,
            'total_amount': session.totalAmount,
            'status': 'created',
            'payment_status': 'unpaid', // FIX: consistent with staff order
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

      // 2. Insert order_items
      if (session.items.isNotEmpty) {
        final orderItemsData = session.items.map((cartItem) {
          final itemData = <String, dynamic>{
            'order_id': orderId,
            'menu_item_id': cartItem.menuItem.id,
            'menu_item_name': cartItem.menuItem.name,
            'unit_price': cartItem.menuItem.price,
            'quantity': cartItem.quantity,
            // subtotal is not inserted because it's a generated column in Supabase
          };
          if (cartItem.notes != null && cartItem.notes!.isNotEmpty) {
            itemData['special_requests'] = cartItem.notes;
          }
          return itemData;
        }).toList();

await _client.from('order_items').insert(orderItemsData);
        debugPrint('✅ ${orderItemsData.length} items saved');

        // Inventory is deducted in order_screen.dart when status → preparing.
        // Not deducted here to avoid double deduction.
      }

      // 3. Update table status IMMEDIATELY after insert
      if (session.tableId.isNotEmpty) {
        try {
          debugPrint('🔍 tableId to be updated: "${session.tableId}"');

          // First check whether the table exists and its current status
          final checkResult = await _client
              .from('restaurant_tables')
              .select('id, status')
              .eq('id', session.tableId)
              .maybeSingle();
          debugPrint('🔍 Table found: $checkResult');

          if (checkResult != null) {
            // ✅ FIX: removed .select() from update — this was causing it to return []
            await _client
                .from('restaurant_tables')
                .update({
                  'status': 'occupied',
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', session.tableId);
            debugPrint('✅ Update complete');

            // Verify with a separate query
            final verify = await _client
                .from('restaurant_tables')
                .select('id, status')
                .eq('id', session.tableId)
                .maybeSingle();
            debugPrint('✅ Table status after update: ${verify?['status']}');
          } else {
            debugPrint('⚠️ Table not found with id: ${session.tableId}');
          }
        } catch (e) {
          debugPrint('⚠️ Failed to update table status: $e');
        }
      } else {
        debugPrint('⚠️ tableId is empty, skipping table update');
      }

      // 4. Re-fetch the order along with its items
      await Future.delayed(const Duration(milliseconds: 500));
      QrOrderModel? fullOrder = await fetchOrder(orderId);

      if (fullOrder != null) {
        debugPrint('✅ Order created: ${fullOrder.items.length} items, total ${fullOrder.totalAmount}');
        return fullOrder;
      }

      // Fallback if the fetch fails
      return QrOrderModel.fromMap(_normalizeOrderMap(orderResponse, const []));

    } catch (e, stack) {
      debugPrint('❌ Failed to create order: $e\n$stack');
      rethrow;
    }
  }

  // ─── Add Items to Existing Order ──────────────────────────────────────────
  /// Adds new items to an existing order (add order).
  /// May only be called while the order status is still `created`.
  /// Existing items are NOT modified at all.
  Future<QrOrderModel> addItemsToOrder({
    required String orderId,
    required List<QrCartItem> newItems,
  }) async {
    if (newItems.isEmpty) throw Exception('No new items to add');

    try {
      debugPrint('🔄 Adding ${newItems.length} item(s) to order $orderId');

      // 1. Check order status — must be `created`
      //    Also make sure no item has already been sent_to_kitchen (extra guard)
      final orderCheck = await _client
          .from('orders')
          .select('id, status, total_amount, subtotal')
          .eq('id', orderId)
          .single();

      final currentStatus = orderCheck['status'] as String;
      if (currentStatus != 'created') {
        throw Exception(
          'Order cannot be changed because it already has status "$currentStatus". '
          'Only orders that have not yet been sent to the kitchen can be added to.',
        );
      }

      // 2. Insert the new items into order_items
      //    `sent_to_kitchen_at` left null → new items not yet sent to the kitchen
      final orderItemsData = newItems.map((cartItem) {
        final itemData = <String, dynamic>{
          'order_id': orderId,
          'menu_item_id': cartItem.menuItem.id,
          'menu_item_name': cartItem.menuItem.name,
          'unit_price': cartItem.menuItem.price,
          'quantity': cartItem.quantity,
          // subtotal is a generated column in the DB, no need to insert it
          // sent_to_kitchen_at: null (not sent yet, staff will send it)
        };
        if (cartItem.notes != null && cartItem.notes!.isNotEmpty) {
          itemData['special_requests'] = cartItem.notes;
        }
        return itemData;
      }).toList();

      await _client.from('order_items').insert(orderItemsData);
      debugPrint('✅ ${orderItemsData.length} new item(s) saved');

      // 3. Re-fetch all items to recompute the total
      final allItemsResp = await _client
          .from('order_items')
          .select('id, menu_item_id, menu_item_name, unit_price, quantity, subtotal, special_requests')
          .eq('order_id', orderId);

      // 4. Recompute the total from all items (old + new)
      //    Formula: subtotal → service_charge 3% → pb1 10% of (subtotal + SC)
      double newSubtotal = 0;
      for (final item in allItemsResp) {
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
        final qty = (item['quantity'] as int?) ?? 0;
        newSubtotal += unitPrice * qty;
      }
      final newServiceCharge = newSubtotal * 0.03;
      final newPb1 = (newSubtotal + newServiceCharge) * 0.10;
      final newTotal = newSubtotal + newServiceCharge + newPb1;

      // 5. Update all financial columns on orders
      //    Per the DB schema: subtotal, service_charge_amount, pb1_amount,
      //    tax_amount (set to pb1 to stay consistent with createOrder), total_amount
      await _client.from('orders').update({
        'subtotal': newSubtotal,
        'service_charge_amount': newServiceCharge,
        'pb1_amount': newPb1,
        'tax_amount': newPb1,   // consistent with createOrder, which uses tax_amount = pb1
        'total_amount': newTotal,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);

      debugPrint('✅ Total updated: Rp ${newTotal.toStringAsFixed(0)}');

      // 6. Re-fetch the full order
      await Future.delayed(const Duration(milliseconds: 300));
      final fullOrder = await fetchOrder(orderId);
      if (fullOrder == null) throw Exception('Failed to load order after update');

      return fullOrder;
    } catch (e, stack) {
      debugPrint('❌ Failed addItemsToOrder: $e\n$stack');
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

  // ── Fetch order + items (TWO SEPARATE QUERIES) ─────────────────────────────
  Future<QrOrderModel?> fetchOrder(String orderId) async {
    final orderResp = await _client
        .from('orders')
        .select(
          'id, order_number, queue_number, table_id, table_name, '
          'customer_name, customer_phone, total_amount, status, payment_status, '
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

  // ── Active order for a table (prevents disconnected duplicate orders when
  // the same table's QR is scanned again while an order is already open) ──
  Future<QrOrderModel?> fetchActiveOrderForTable(String tableId) async {
    final orderResp = await _client
        .from('orders')
        .select(
          'id, order_number, queue_number, table_id, table_name, '
          'customer_name, customer_phone, total_amount, status, payment_status, '
          'payment_method, created_at, updated_at, branch_id, notes',
        )
        .eq('table_id', tableId)
        .not('status', 'in', '(paid,cancelled)')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (orderResp == null) return null;

    final itemsResp = await _client
        .from('order_items')
        .select('id, menu_item_id, menu_item_name, unit_price, quantity, subtotal, special_requests')
        .eq('order_id', orderResp['id'] as String);

    return QrOrderModel.fromMap(_normalizeOrderMap(orderResp, itemsResp));
  }

  Future<QrOrderModel?> fetchByQueueNumber(String queueNumber) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final orderResp = await _client
        .from('orders')
        .select(
          'id, order_number, queue_number, table_id, table_name, '
          'customer_name, customer_phone, total_amount, status, payment_status, '
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
      // Make sure BOTH keys are available so fromMap can read unit_price or price
      final unitPrice = item['unit_price'] ?? item['price'];
      item['unit_price'] = unitPrice;
      item['price'] = unitPrice;
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
      // 1. Fetch menu items (only available)
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

      if (items.isEmpty) return [];

      final menuIds = (items as List).map((e) => e['id'] as String).toList();

      // 2. Fetch allergens & dietary tags in parallel
      final results = await Future.wait([
        _client
            .from('menu_item_allergens')
            .select('menu_item_id, allergen')
            .inFilter('menu_item_id', menuIds),
        _client
            .from('menu_item_dietary')
            .select('menu_item_id, dietary_tag')
            .inFilter('menu_item_id', menuIds),
      ]);

      // 3. Build lookup maps
      final Map<String, List<String>> allergenMap = {};
      for (final row in results[0]) {
        final id = row['menu_item_id'] as String;
        allergenMap.putIfAbsent(id, () => []).add(row['allergen'] as String);
      }

      final Map<String, List<String>> dietaryMap = {};
      for (final row in results[1]) {
        final id = row['menu_item_id'] as String;
        dietaryMap.putIfAbsent(id, () => []).add(row['dietary_tag'] as String);
      }

      // 4. Merge into each item
      return items.map<Map<String, dynamic>>((item) {
        final id = item['id'] as String;
        return {
          ...Map<String, dynamic>.from(item as Map),
          'allergens': allergenMap[id] ?? [],
          'dietary_tags': dietaryMap[id] ?? [],
        };
      }).toList();

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
    final now = DateTime.now().toUtc();
    // Use UTC midnight to stay consistent with Supabase timestamps (UTC)
    final startOfDayUtc = DateTime.utc(now.year, now.month, now.day);
    try {
      final rows = await _client
          .from('orders')
          .select('queue_number')
          .eq('branch_id', branchId)
          .gte('created_at', startOfDayUtc.toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);

      if (rows.isEmpty) return 'A001';
      final lastQueue = rows.first['queue_number'] as String;
      if (lastQueue.length < 2) return 'A001';
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

// ─── Add Items Notifier ────────────────────────────────────────────────────────
/// Provider for adding items to an existing order.
/// State: AsyncValue<QrOrderModel?> — null = idle, loading, data, error
class QrAddItemsNotifier extends StateNotifier<AsyncValue<QrOrderModel?>> {
  final QrOrderRepository _repo;
  QrAddItemsNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<QrOrderModel?> submit({
    required String orderId,
    required List<QrCartItem> newItems,
  }) async {
    state = const AsyncValue.loading();
    try {
      final updated = await _repo.addItemsToOrder(
        orderId: orderId,
        newItems: newItems,
      );
      state = AsyncValue.data(updated);
      return updated;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  void reset() => state = const AsyncValue.data(null);
}

final qrAddItemsProvider =
    StateNotifierProvider<QrAddItemsNotifier, AsyncValue<QrOrderModel?>>(
  (ref) => QrAddItemsNotifier(ref.read(qrOrderRepositoryProvider)),
);