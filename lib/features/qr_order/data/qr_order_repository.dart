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
    // Step 1: Ambil menu_items tanpa join (hindari 400 dari PostgREST FK join)
    final items = await _client
        .from('menu_items')
        .select(
          'id, branch_id, category_id, name, description, price, '
          'image_url, is_available, is_seasonal, '
          'preparation_time_minutes, sort_order, created_at, updated_at',
        )
        .eq('branch_id', branchId)
        .eq('is_available', true)
        .order('sort_order');

    final itemList = List<Map<String, dynamic>>.from(items);
    if (itemList.isEmpty) return itemList;

    // Step 2: Kumpulkan category_id unik
    final categoryIds = itemList
        .map((i) => i['category_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    // Step 3: Fetch categories terpisah
    Map<String, Map<String, dynamic>> categoryMap = {};
    if (categoryIds.isNotEmpty) {
      try {
        final categories = await _client
            .from('menu_categories')
            .select('id, name, sort_order')
            .inFilter('id', categoryIds);
        for (final cat in List<Map<String, dynamic>>.from(categories)) {
          categoryMap[cat['id'] as String] = cat;
        }
      } catch (_) {
        // Lanjut tanpa kategori jika gagal
      }
    }

    // Step 4: Gabungkan manual
    return itemList.map((item) {
      final catId = item['category_id'] as String?;
      return {
        ...item,
        'menu_categories': catId != null ? categoryMap[catId] : null,
      };
    }).toList();
  }

  // ─── Fetch Table Info ───────────────────────────────────────────────────────
  // FIX: Ganti FK join PostgREST `branches(name, id)` → 2-step query terpisah.
  // FK join gagal di mobile karena RLS anon/public role tidak punya permission
  // untuk resolve foreign key ke tabel `branches` secara langsung via PostgREST.

  Future<Map<String, dynamic>?> fetchTableInfo(String tableId) async {
    // Step 1: Ambil data meja tanpa join
    final tableRow = await _client
        .from('restaurant_tables')
        .select('id, table_number, branch_id, status, capacity, description')
        .eq('id', tableId)
        .maybeSingle();

    if (tableRow == null) return null;

    // Step 2: Ambil branch secara terpisah menggunakan branch_id dari meja
    final branchId = tableRow['branch_id'] as String?;
    Map<String, dynamic>? branchData;
    if (branchId != null && branchId.isNotEmpty) {
      try {
        branchData = await _client
            .from('branches')
            .select('id, name')
            .eq('id', branchId)
            .maybeSingle();
      } catch (_) {
        // Lanjut tanpa nama branch — branchId tetap ada untuk load menu
      }
    }

    // Step 3: Gabungkan dengan struktur yang sama persis dengan FK join
    // sehingga kode di qr_menu_screen.dart tidak perlu diubah sama sekali
    return {
      ...tableRow,
      'branches': branchData,
    };
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