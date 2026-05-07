// lib/features/multi_branch/services/transfer_stock_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/transfer_stock_model.dart';

class TransferStockService {
  final SupabaseClient _client;

  TransferStockService(this._client);

  // ─── FETCH ────────────────────────────────────────────────────────────────

  /// Fetch semua transfer yang relevan untuk branch ini
  /// (sebagai pengirim ATAU penerima)
  Future<List<TransferStockModel>> fetchTransfers({
    required String branchId,
    TransferStatus? filterStatus,
  }) async {
    var query = _client
        .from('inventory_transfers')
        .select('''
          id, from_branch_id, to_branch_id, item_id,
          quantity, status, requested_by, approved_by,
          created_at, received_at,
          inventory_items!item_id ( name, unit ),
          from_branch:branches!from_branch_id ( name ),
          to_branch:branches!to_branch_id ( name ),
          requester:staff!requested_by ( full_name ),
          approver:staff!approved_by ( full_name )
        ''');

    if (filterStatus != null) {
      query = query.eq('status', filterStatus.name);
    }

    // Tampilkan yang relevan dengan branch ini
    // (from_branch_id = branchId OR to_branch_id = branchId)
    final res = await query.order('created_at', ascending: false);

    final all = (res as List).map((e) {
      final map = e as Map<String, dynamic>;
      final item       = map['inventory_items'] as Map<String, dynamic>?;
      final fromBranch = map['from_branch']     as Map<String, dynamic>?;
      final toBranch   = map['to_branch']       as Map<String, dynamic>?;
      final requester  = map['requester']        as Map<String, dynamic>?;
      final approver   = map['approver']         as Map<String, dynamic>?;

      return TransferStockModel.fromMap({
        ...map,
        'item_name':          item?['name'],
        'item_unit':          item?['unit'],
        'from_branch_name':   fromBranch?['name'],
        'to_branch_name':     toBranch?['name'],
        'requested_by_name':  requester?['full_name'],
        'approved_by_name':   approver?['full_name'],
      });
    }).toList();

    // Filter hanya yang melibatkan branch ini
    return all.where((t) =>
      t.fromBranchId == branchId || t.toBranchId == branchId,
    ).toList();
  }

  /// Fetch inventory items milik branch tertentu (untuk dropdown pilih item)
  Future<List<Map<String, dynamic>>> fetchItemsForBranch(String branchId) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final res = await _client
        .from('inventory_items')
        .select('id, name, unit, current_stock')
        .eq('branch_id', branchId)
        .eq('date', today)
        .order('name');
    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Fetch branches lain (selain branch asal) untuk dropdown tujuan
  Future<List<Map<String, dynamic>>> fetchOtherBranches(String excludeBranchId) async {
    final res = await _client
        .from('branches')
        .select('id, name')
        .eq('is_active', true)
        .neq('id', excludeBranchId)
        .order('name');
    return (res as List).cast<Map<String, dynamic>>();
  }

  // ─── WRITE ────────────────────────────────────────────────────────────────

  /// Request transfer stok (oleh manager/superadmin branch asal)
  Future<void> requestTransfer({
    required String fromBranchId,
    required String toBranchId,
    required String itemId,
    required double quantity,
    required String requestedBy,
  }) async {
    // 1. Insert ke inventory_transfers
    await _client.from('inventory_transfers').insert({
      'from_branch_id': fromBranchId,
      'to_branch_id':   toBranchId,
      'item_id':        itemId,
      'quantity':       quantity,
      'status':         'pending',
      'requested_by':   requestedBy,
    });

    // 2. Catat transfer_out di inventory_items branch asal
    await _client.from('inventory_items').update({
      'transfer_out': _client.rpc('increment_field_value'),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Pakai RPC untuk increment transfer_out
    await _incrementField(itemId: itemId, field: 'transfer_out', amount: quantity);
  }

  /// Konfirmasi terima transfer (oleh manager/superadmin branch tujuan)
  Future<void> approveTransfer({
    required String transferId,
    required String toItemId,   // item_id di branch tujuan (item yang sama)
    required String approvedBy,
    required double quantity,
  }) async {
    final now = DateTime.now().toIso8601String();

    // 1. Update status transfer → received
    await _client.from('inventory_transfers').update({
      'status':      'received',
      'approved_by': approvedBy,
      'received_at': now,
    }).eq('id', transferId);

    // 2. Tambah transfer_in di inventory_items branch tujuan
    await _incrementField(itemId: toItemId, field: 'transfer_in', amount: quantity);
  }

  /// Batalkan transfer (hanya jika masih pending)
  Future<void> cancelTransfer(String transferId) async {
    // Ambil data transfer dulu untuk rollback transfer_out
    final res = await _client
        .from('inventory_transfers')
        .select('item_id, quantity, status')
        .eq('id', transferId)
        .single();

    if (res['status'] != 'pending') {
      throw Exception('Hanya transfer dengan status pending yang bisa dibatalkan.');
    }

    // Rollback transfer_out di branch asal
    await _incrementField(
      itemId: res['item_id'] as String,
      field: 'transfer_out',
      amount: -((res['quantity'] as num).toDouble()), // negatif = kurangi
    );

    // Update status → cancelled
    await _client.from('inventory_transfers').update({
      'status': 'cancelled',
    }).eq('id', transferId);
  }

  // ─── PRIVATE ──────────────────────────────────────────────────────────────

  Future<void> _incrementField({
    required String itemId,
    required String field,
    required double amount,
  }) async {
    try {
      await _client.rpc('increment_inventory_field', params: {
        'p_id':     itemId,
        'p_field':  field,
        'p_amount': amount,
      });
    } catch (_) {
      // Fallback: manual update jika RPC belum ada
      final current = await _client
          .from('inventory_items')
          .select(field)
          .eq('id', itemId)
          .single();
      final currentVal = (current[field] as num?)?.toDouble() ?? 0.0;
      await _client.from('inventory_items').update({
        field: currentVal + amount,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', itemId);
    }
  }
}