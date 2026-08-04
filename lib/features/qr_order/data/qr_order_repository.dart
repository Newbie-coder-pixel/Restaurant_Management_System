import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/qr_order_model.dart';
import '../providers/qr_cart_provider.dart';
import '../../../shared/models/order_model.dart';
import '../../../shared/utils/branch_hours.dart';
import '../../../shared/services/order_number_service.dart';

/// Thrown when a customer tries to place/add to an order while the branch is
/// outside its operating hours. Kept separate from a generic Exception so
/// callers could special-case it later if needed; today the screens just
/// display its message as-is (see QrOrderRepository's doc comment above
/// enforce_branch_open_for_order_insert in the matching migration).
class QrRestaurantClosedException implements Exception {
  final String? openingTime;
  final String? closingTime;
  QrRestaurantClosedException({this.openingTime, this.closingTime});

  @override
  String toString() {
    if (openingTime == null || closingTime == null) {
      return 'This restaurant is currently closed. Please order again during operating hours.';
    }
    return 'This restaurant is currently closed (opens ${formatHhMm(openingTime)}–'
        '${formatHhMm(closingTime)}). Please order again during operating hours.';
  }
}

class QrOrderRepository {
  final SupabaseClient _client;

  QrOrderRepository(this._client);

  // ── Re-check (fresh, not cached) that a branch is open right now — called
  // right before every order-creating write so a customer who's been sitting
  // on a stale bookmarked QR link (or just idling past closing time with the
  // menu already loaded) can't slip an order in between the client-side gate
  // rendering and the actual insert. This is a UX nicety only: the Postgres
  // triggers are what actually make this unbypassable against a direct REST
  // call with the anon key.
  Future<void> _assertBranchOpen(String branchId) async {
    if (branchId.trim().isEmpty) return;
    final branch = await _client
        .from('branches')
        .select('opening_time, closing_time')
        .eq('id', branchId)
        .maybeSingle();
    if (branch == null) return;
    final opening = branch['opening_time'] as String?;
    final closing = branch['closing_time'] as String?;
    if (!isBranchOpen(openingTime: opening, closingTime: closing)) {
      throw QrRestaurantClosedException(openingTime: opening, closingTime: closing);
    }
  }

  // ─── Create Order ──────────────────────────────────────────────────────────
  Future<QrOrderModel> createOrder({
    required QrOrderSession session,
    required String branchId,
    String? notes,
    String? deviceId,
  }) async {
    await _assertBranchOpen(branchId);
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
            if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
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
          .select('id, status, total_amount, subtotal, branch_id')
          .eq('id', orderId)
          .single();

      final currentStatus = orderCheck['status'] as String;
      if (currentStatus != 'created') {
        throw Exception(
          'Order cannot be changed because it already has status "$currentStatus". '
          'Only orders that have not yet been sent to the kitchen can be added to.',
        );
      }

      // The original order may have been placed while the branch was open;
      // re-check now in case it closed in the meantime (e.g. customer keeps
      // adding items well past closing time).
      await _assertBranchOpen(orderCheck['branch_id'] as String? ?? '');

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

  // ── Claim an ownerless order (device_id IS NULL) for this device ───────────
  // Orders placed before the device-lock feature shipped (or any other order
  // that somehow never got a device_id recorded at insert time) have no way
  // to prove who placed them. Rather than permanently locking every device
  // out of such an order, the first device to open it claims it — exactly
  // what would have happened at insert time. The DB only allows this
  // transition when device_id is currently null (see
  // 20260803030000_qr_order_device_id_claim.sql); it can't be used to steal
  // an order that already has an owner.
  Future<void> claimOrderIfUnowned(String orderId, String deviceId) async {
    try {
      await _client
          .from('orders')
          .update({'device_id': deviceId})
          .eq('id', orderId)
          .isFilter('device_id', null);
    } catch (e) {
      debugPrint('⚠️ claimOrderIfUnowned failed (non-fatal): $e');
    }
  }

  // ── Fetch order + items (TWO SEPARATE QUERIES) ─────────────────────────────
  // customer_phone deliberately not selected — QrOrderModel has no field for
  // it (dead weight over the wire) and, unlike fetchOrderModelForPayment,
  // this path isn't used for anything that needs it.
  Future<QrOrderModel?> fetchOrder(String orderId) async {
    final orderResp = await _client
        .from('orders')
        .select(
          'id, order_number, queue_number, table_id, table_name, '
          'customer_name, total_amount, status, payment_status, '
          'payment_method, created_at, updated_at, branch_id, notes, device_id',
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
          'customer_name, total_amount, status, payment_status, '
          'payment_method, created_at, updated_at, branch_id, notes, device_id',
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

  // ── Fetch as OrderModel for self-service Midtrans payment ──────────────────
  // Same select shape as the staff cashier screen's query, so OrderModel's
  // overtime-charge math (which depends on `served_at`) and totals behave
  // identically regardless of who — staff or the customer's own device —
  // initiates the Midtrans payment. See MidtransService.createSnapToken and
  // supabase/functions/midtrans-create-token, which independently recompute
  // the same formula server-side and must match what's shown here.
  Future<OrderModel> fetchOrderModelForPayment(String orderId) async {
    final row = await _client
        .from('orders')
        .select('''
          id, branch_id, table_id, order_number,
          status, source, order_type, customer_name,
          customer_phone, queue_number, table_name,
          discount_amount, notes, created_at, updated_at, served_at,
          payment_status, bill_requested, bill_requested_at,
          total_amount, subtotal, tax_amount,
          restaurant_tables(table_number),
          order_items(*)
        ''')
        .eq('id', orderId)
        .single();

    return OrderModel.fromJson(row);
  }

  // Goes through the get_order_by_number RPC rather than a direct table
  // SELECT — this is reachable with no login and a guessable "A001"-style
  // number, so it must never be able to return more than the one exact
  // match, and must never expose customer_phone/customer_email (see
  // supabase/migrations/20260805040000_get_order_by_number_rpc.sql — a
  // direct SELECT here was, until this fix, live-exploitable to dump every
  // customer's name/phone/email from the last 24 hours with no filter at all).
  Future<QrOrderModel?> fetchByQueueNumber(String queueNumber) async {
    final rows = await _client.rpc('get_order_by_number', params: {
      'p_order_number': queueNumber,
    }) as List<dynamic>;
    if (rows.isEmpty) return null;
    final orderResp = rows.first as Map<String, dynamic>;

    // queue_number/order_number ("A001") is reused across different days —
    // only accept a match from today, same as the old query's date filter.
    final createdAt = DateTime.tryParse(orderResp['created_at'] as String);
    final today = DateTime.now();
    if (createdAt == null ||
        createdAt.year != today.year ||
        createdAt.month != today.month ||
        createdAt.day != today.day) {
      return null;
    }

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
          .select('*, branches(id, name, opening_time, closing_time)')
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

  // ── Report a table status mismatch from the QR gate ─────────────────────
  // e.g. status says "cleaning" but the table looks fine to the customer, or
  // vice versa. Staff see a badge on the table card; it's cleared the next
  // time staff changes that table's status (see table_screen.dart
  // _updateStatus). Anon may only ever set this column and status=occupied
  // on restaurant_tables — see 20260803040000_table_status_gate_and_anon_lockdown.sql.
  Future<void> reportTableIssue(String tableId) async {
    await _client
        .from('restaurant_tables')
        .update({'customer_reported_at': DateTime.now().toIso8601String()})
        .eq('id', tableId);
  }

  // Reserves this branch/day's next number from the ONE counter shared with
  // the customer app and staff cashier (see OrderNumberService), then
  // formats it into the "A001" look QR queue numbers have always had. No
  // fallback-to-random on error anymore — that was the exact race/collision
  // risk this shared counter exists to remove; a failed reservation now
  // surfaces as a real error instead of a silently-duplicate-prone number.
  Future<String> _generateQueueNumber(String branchId) async {
    final result = await OrderNumberService.nextSequence(branchId);
    return OrderNumberService.formatQrQueueNumber(result.seq);
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