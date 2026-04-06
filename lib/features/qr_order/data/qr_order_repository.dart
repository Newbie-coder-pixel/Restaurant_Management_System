import 'dart:math';
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
  }) async {
    // Generate queue number: 3-digit daily sequence, e.g. A001
    final queueNumber = await _generateQueueNumber(branchId);

    final orderData = {
      'queue_number': queueNumber,
      'table_id': session.tableId,
      'table_name': session.tableName ?? 'Meja ${session.tableId}',
      'customer_name': session.customerName ?? 'Tamu',
      'items': session.items
          .map((i) => {
                'menu_item_id': i.menuItem.id,
                'menu_item_name': i.menuItem.name,
                'price': i.menuItem.price,
                'quantity': i.quantity,
                if (i.notes != null && i.notes!.isNotEmpty) 'notes': i.notes,
                if (i.menuItem.imageUrl != null)
                  'image_url': i.menuItem.imageUrl,
              })
          .toList(),
      'total_amount': session.totalAmount,
      'status': QrOrderStatus.pending.name,
      'payment_status': QrPaymentStatus.unpaid.name,
      'payment_method': session.paymentMethod?.name ?? 'kasir',
      'branch_id': branchId,
      'order_type': 'walk_in',
      'created_at': DateTime.now().toIso8601String(),
    };

    final response = await _client
        .from('orders')
        .insert(orderData)
        .select()
        .single();

    return QrOrderModel.fromMap(response);
  }

  // ─── Realtime Stream ────────────────────────────────────────────────────────

  Stream<QrOrderModel> watchOrder(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) {
          if (rows.isEmpty) throw Exception('Order tidak ditemukan');
          return QrOrderModel.fromMap(rows.first);
        });
  }

  // ─── Fetch Single ───────────────────────────────────────────────────────────

  Future<QrOrderModel?> fetchOrder(String orderId) async {
    final response = await _client
        .from('orders')
        .select()
        .eq('id', orderId)
        .maybeSingle();
    if (response == null) return null;
    return QrOrderModel.fromMap(response);
  }

  // ─── Fetch by Queue Number ──────────────────────────────────────────────────

  Future<QrOrderModel?> fetchByQueueNumber(String queueNumber) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final response = await _client
        .from('orders')
        .select()
        .eq('queue_number', queueNumber)
        .gte('created_at', startOfDay.toIso8601String())
        .maybeSingle();
    if (response == null) return null;
    return QrOrderModel.fromMap(response);
  }

  // ─── Fetch Menu Items by Branch ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMenuByBranch(String branchId) async {
    final response = await _client
        .from('menu_items')
        .select('*, menu_categories(name, sort_order)')
        .eq('branch_id', branchId)
        .eq('is_available', true)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(response);
  }

  // ─── Fetch Table Info ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> fetchTableInfo(String tableId) async {
    final response = await _client
        .from('restaurant_tables')
        .select('*, branches(name, id)')
        .eq('id', tableId)
        .maybeSingle();
    return response;
  }

  // ─── Private: Generate Queue Number ────────────────────────────────────────

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
      // Format: A001, A002 ... A999, B001 ...
      final letter = lastQueue[0];
      final number = int.tryParse(lastQueue.substring(1)) ?? 0;

      if (number < 999) {
        return '$letter${(number + 1).toString().padLeft(3, '0')}';
      } else {
        final nextLetter = String.fromCharCode(letter.codeUnitAt(0) + 1);
        return '${nextLetter}001';
      }
    } catch (_) {
      // Fallback: random 3-digit
      final rnd = Random().nextInt(999) + 1;
      return 'A${rnd.toString().padLeft(3, '0')}';
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final qrOrderRepositoryProvider = Provider<QrOrderRepository>((ref) {
  return QrOrderRepository(Supabase.instance.client);
});

// ─── Order creation state ──────────────────────────────────────────────────

class QrOrderCreationNotifier
    extends StateNotifier<AsyncValue<QrOrderModel?>> {
  final QrOrderRepository _repo;

  QrOrderCreationNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<QrOrderModel?> submit({
    required QrOrderSession session,
    required String branchId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final order = await _repo.createOrder(
        session: session,
        branchId: branchId,
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

// ─── Realtime watch ────────────────────────────────────────────────────────

final qrOrderWatchProvider =
    StreamProvider.family<QrOrderModel, String>((ref, orderId) {
  final repo = ref.read(qrOrderRepositoryProvider);
  return repo.watchOrder(orderId);
});