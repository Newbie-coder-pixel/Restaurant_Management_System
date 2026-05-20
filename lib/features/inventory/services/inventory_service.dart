// lib/features/inventory/services/inventory_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_item.dart';

class InventoryService {
  final SupabaseClient _client;

  InventoryService(this._client);

  // ─── FETCH ────────────────────────────────────────────────────────────────

  Future<List<InventoryItem>> fetchInventoryItems({
    required String branchId,
    DateTime? date,
  }) async {
    final targetDate = date ?? DateTime.now();
    final dateStr = targetDate.toIso8601String().split('T').first;

    final response = await _client
        .from('inventory_items')
        .select()
        .eq('branch_id', branchId)
        .eq('date', dateStr)
        .order('category')
        .order('name');

    return (response as List)
        .map((e) => InventoryItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Stream<List<InventoryItem>> streamInventoryItems({
    required String branchId,
    DateTime? date,
  }) {
    final dateStr =
        (date ?? DateTime.now()).toIso8601String().split('T').first;

    return _client
        .from('inventory_items')
        .stream(primaryKey: ['id'])
        .eq('branch_id', branchId)
        .order('name')
        .map((rows) => rows
            .where((r) => r['date'] == dateStr)
            .map((e) => InventoryItem.fromMap(e))
            .toList());
  }

  Future<List<InventoryItem>> fetchLowStockItems(String branchId) async {
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final response = await _client
        .from('inventory_items')
        .select()
        .eq('branch_id', branchId)
        .eq('date', dateStr);

    final items = (response as List)
        .map((e) => InventoryItem.fromMap(e as Map<String, dynamic>))
        .toList();

    return items.where((item) => item.isLowStock || item.isOutOfStock).toList();
  }

  Future<List<InventoryTransaction>> fetchTransactions({
    required String inventoryItemId,
    int limit = 50,
  }) async {
    final response = await _client
        .from('inventory_transactions')
        .select()
        .eq('inventory_item_id', inventoryItemId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (response as List)
        .map((e) => InventoryTransaction.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // ─── WRITE ────────────────────────────────────────────────────────────────

  Future<InventoryItem> addInventoryItem(InventoryItem item) async {
    final response = await _client
        .from('inventory_items')
        .insert(item.toMap())
        .select()
        .single();

    return InventoryItem.fromMap(response);
  }

  Future<InventoryItem> updateInventoryItem(InventoryItem item) async {
    final response = await _client
        .from('inventory_items')
        .update(item.toMap())
        .eq('id', item.id)
        .select()
        .single();

    return InventoryItem.fromMap(response);
  }

  Future<void> recordPurchase({
    required String inventoryItemId,
    required String branchId,
    required double quantity,
    String? note,
    String? createdBy,
  }) async {
    await _client.rpc('increment_inventory_field', params: {
      'p_id': inventoryItemId,
      'p_field': 'purchased_stock',
      'p_amount': quantity,
    });

    await _logTransaction(
      inventoryItemId: inventoryItemId,
      branchId: branchId,
      type: 'purchase',
      quantity: quantity,
      note: note,
      createdBy: createdBy,
    );
  }

  /// Dipanggil dari order_screen saat order → preparing.
  /// [menuItemName] diisi nama menu agar histori terpakai lebih informatif.
  Future<void> deductFromOrder({
    required String inventoryItemId,
    required String branchId,
    required double quantity,
    required String orderId,
    String? menuItemName,       // ← BARU: nama menu untuk kolom menu_item_name
    String? createdBy,
  }) async {
    await _client.rpc('increment_inventory_field', params: {
      'p_id': inventoryItemId,
      'p_field': 'used_stock',
      'p_amount': quantity,
    });

    await _logTransaction(
      inventoryItemId: inventoryItemId,
      branchId: branchId,
      type: 'order_deduct',
      quantity: quantity,
      referenceId: orderId,
      note: menuItemName != null ? 'Dari order: $menuItemName' : 'Deducted from order',
      createdBy: createdBy,
      menuItemName: menuItemName,   // ← BARU
    );

    await _checkAndUpdateMenuAvailability(inventoryItemId, branchId);
  }

  Future<void> recordWaste({
    required String inventoryItemId,
    required String branchId,
    required double quantity,
    String? note,
    String? createdBy,
  }) async {
    await _client.rpc('increment_inventory_field', params: {
      'p_id': inventoryItemId,
      'p_field': 'waste_stock',
      'p_amount': quantity,
    });

    await _logTransaction(
      inventoryItemId: inventoryItemId,
      branchId: branchId,
      type: 'waste',
      quantity: quantity,
      note: note ?? 'Waste/Spoilage',
      createdBy: createdBy,
    );
  }

  Future<void> transferStock({
    required String fromItemId,
    required String fromBranchId,
    required String toItemId,
    required String toBranchId,
    required double quantity,
    String? createdBy,
  }) async {
    await _client.rpc('increment_inventory_field', params: {
      'p_id': fromItemId,
      'p_field': 'transfer_out',
      'p_amount': quantity,
    });

    await _client.rpc('increment_inventory_field', params: {
      'p_id': toItemId,
      'p_field': 'transfer_in',
      'p_amount': quantity,
    });

    final transferId = DateTime.now().millisecondsSinceEpoch.toString();
    await _logTransaction(
      inventoryItemId: fromItemId,
      branchId: fromBranchId,
      type: 'transfer_out',
      quantity: quantity,
      referenceId: transferId,
      note: 'Transfer to branch: $toBranchId',
      createdBy: createdBy,
    );
    await _logTransaction(
      inventoryItemId: toItemId,
      branchId: toBranchId,
      type: 'transfer_in',
      quantity: quantity,
      referenceId: transferId,
      note: 'Transfer from branch: $fromBranchId',
      createdBy: createdBy,
    );
  }

  Future<void> adjustStock({
    required String inventoryItemId,
    required String branchId,
    required double adjustmentQty,
    required String reason,
    String? createdBy,
  }) async {
    await _client
        .from('inventory_items')
        .update({
          'adjustment_stock': adjustmentQty,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', inventoryItemId);

    await _logTransaction(
      inventoryItemId: inventoryItemId,
      branchId: branchId,
      type: 'adjustment',
      quantity: adjustmentQty,
      note: reason,
      createdBy: createdBy,
    );
  }

  /// Roll over stok akhir → stok awal hari berikutnya.
  /// ✅ FIX: carry over unit_secondary & unit_conversion
  Future<void> rolloverDailyStock(String branchId) async {
    final tomorrow = DateTime.now()
        .add(const Duration(days: 1))
        .toIso8601String()
        .split('T')
        .first;

    final items = await fetchInventoryItems(branchId: branchId);

    final inserts = items.map((item) {
      return {
        'branch_id': branchId,
        'name': item.name,
        'unit': item.unit,
        'category': item.category,
        'opening_stock': item.closingStock,
        'used_stock': 0.0,
        'waste_stock': 0.0,
        'purchased_stock': 0.0,
        'transfer_in': 0.0,
        'transfer_out': 0.0,
        'adjustment_stock': 0.0,
        'minimum_stock': item.minimumStock,
        'cost_per_unit': item.costPerUnit,
        'linked_menu_ids': item.linkedMenuIds,
        'date': tomorrow,
        // ✅ FIX: carry over satuan sekunder
        'unit_secondary': item.unitSecondary,
        'unit_conversion': item.unitConversion,
      };
    }).toList();

    if (inserts.isNotEmpty) {
      await _client.from('inventory_items').upsert(inserts,
          onConflict: 'branch_id,name,date');
    }
  }

  // ─── PRIVATE HELPERS ──────────────────────────────────────────────────────

  Future<void> _logTransaction({
    required String inventoryItemId,
    required String branchId,
    required String type,
    required double quantity,
    String? note,
    String? referenceId,
    String? createdBy,
    String? menuItemName,   // ← BARU
  }) async {
    await _client.from('inventory_transactions').insert({
      'inventory_item_id': inventoryItemId,
      'branch_id': branchId,
      'transaction_type': type,
      'quantity': quantity,
      'notes': note,
      'reference_id': referenceId,
      'performed_by': createdBy,
      'menu_item_name': menuItemName,   // ← BARU: nama menu tampil di histori
    });
  }

  Future<void> _checkAndUpdateMenuAvailability(
    String inventoryItemId,
    String branchId,
  ) async {
    try {
      final response = await _client
          .from('inventory_items')
          .select(
              'linked_menu_ids, opening_stock, used_stock, waste_stock, '
              'purchased_stock, transfer_in, transfer_out, adjustment_stock')
          .eq('id', inventoryItemId)
          .single();

      final item = InventoryItem.fromMap({
        ...response,
        'id': inventoryItemId,
        'branch_id': branchId,
        'name': '',
        'unit': 'pcs',
        'category': '',
        'minimum_stock': 0.0,
        'cost_per_unit': 0.0,
        'date': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (item.isOutOfStock && item.linkedMenuIds != null) {
        final menuIds = (item.linkedMenuIds ?? '')
            .replaceAll('[', '')
            .replaceAll(']', '')
            .replaceAll('"', '')
            .split(',')
            .where((id) => id.trim().isNotEmpty)
            .toList();

        for (final menuId in menuIds) {
          await _client
              .from('menus')
              .update({'is_available': false})
              .eq('id', menuId.trim())
              .eq('branch_id', branchId);
        }
      }
    } catch (_) {
      // Tidak crash jika menu update gagal
    }
  }

  Future<InventoryDailySummary> getDailySummary(String branchId,
      {DateTime? date}) async {
    final items = await fetchInventoryItems(branchId: branchId, date: date);

    int lowStock = 0;
    int outOfStock = 0;
    double totalValue = 0;
    double totalUsed = 0;
    double totalWaste = 0;

    for (final item in items) {
      if (item.isOutOfStock) {
        outOfStock++;
      } else if (item.isLowStock) {
        lowStock++;
      }
      totalValue += item.availableStock * item.costPerUnit;
      totalUsed += item.usedStock * item.costPerUnit;
      totalWaste += item.wasteStock * item.costPerUnit;
    }

    return InventoryDailySummary(
      branchId: branchId,
      date: date ?? DateTime.now(),
      totalItems: items.length,
      lowStockItems: lowStock,
      outOfStockItems: outOfStock,
      totalInventoryValue: totalValue,
      totalUsedValue: totalUsed,
      totalWasteValue: totalWaste,
    );
  }
}