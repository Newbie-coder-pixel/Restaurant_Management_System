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
    // branchId is empty for a beat while the staff/branch record is still
    // loading (e.g. right after a hard refresh) — .eq('branch_id', '')
    // against a uuid column is rejected by Postgres with 22P02 ("invalid
    // input syntax for type uuid"), surfacing as an HTTP 400. Same race
    // already seen (and fixed) on the Multi-Branch Overview screen.
    if (branchId.isEmpty) return [];

    final targetDate = date ?? DateTime.now();
    final dateStr = targetDate.toIso8601String().split('T').first;

    final response = await _client
        .from('inventory_items')
        .select()
        .eq('branch_id', branchId)
        .eq('date', dateStr)
        // ✅ FIX: PostgrestTransformBuilder.order() defaults `ascending` to
        // false, so these were silently sorting Z→A instead of A→Z.
        .order('category', ascending: true)
        .order('name', ascending: true);

    return (response as List)
        .map((e) => InventoryItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Stream<List<InventoryItem>> streamInventoryItems({
    required String branchId,
    DateTime? date,
  }) {
    // Same empty-branchId guard as fetchInventoryItems above — an empty
    // filter here would 400 the realtime stream's fallback fetch and tear
    // down its underlying controller.
    if (branchId.isEmpty) return Stream.value(const []);

    final dateStr =
        (date ?? DateTime.now()).toIso8601String().split('T').first;

    return _client
        .from('inventory_items')
        .stream(primaryKey: ['id'])
        .eq('branch_id', branchId)
        // ✅ FIX: SupabaseStreamBuilder.order() also defaults `ascending`
        // to false — same silent Z→A sort bug as fetchInventoryItems.
        .order('name', ascending: true)
        .map((rows) => rows
            .where((r) => r['date'] == dateStr)
            .map((e) => InventoryItem.fromMap(e))
            .toList());
  }

  Future<List<InventoryItem>> fetchLowStockItems(String branchId) async {
    if (branchId.isEmpty) return [];
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

  /// Called from order_screen when an order moves to → preparing.
  /// [menuItemName] holds the menu item name so the usage history is more informative.
  Future<void> deductFromOrder({
    required String inventoryItemId,
    required String branchId,
    required double quantity,
    required String orderId,
    String? menuItemName,       // ← NEW: menu item name for the menu_item_name column
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
      note: menuItemName != null ? 'From order: $menuItemName' : 'Deducted from order',
      createdBy: createdBy,
      menuItemName: menuItemName,   // ← NEW
    );

    await _checkAndUpdateMenuAvailability(inventoryItemId, branchId);
  }

  /// Deduct inventory stock based on the recipe (ingredients per menu item).
  ///
  /// [requirements] = list of ingredient needs: ingredient name (must match
  /// `inventory_items.name` in this branch) + total quantity to deduct
  /// (already multiplied by the order quantity).
  ///
  /// Matched by NAME (not ID) because `inventory_items` is daily (a new row
  /// each day via [rolloverDailyStock]), so the ID stored in a menu recipe
  /// may no longer be valid for today.
  ///
  /// Items whose name isn't found in today's stock are safely skipped
  /// (returned via [notFound]) so a single unregistered ingredient doesn't
  /// fail the whole "start cooking" process.
  Future<List<String>> deductIngredientsForOrder({
    required String branchId,
    required String orderId,
    required Map<String, double> requirements, // ingredient name → qty to deduct
    String? menuItemName,
    String? createdBy,
  }) async {
    if (requirements.isEmpty) return [];

    final todayStock = await fetchInventoryItems(branchId: branchId);
    final byName = <String, InventoryItem>{
      for (final item in todayStock) item.name.trim().toLowerCase(): item,
    };

    final notFound = <String>[];

    for (final entry in requirements.entries) {
      final qty = entry.value;
      if (qty <= 0) continue;

      final match = byName[entry.key.trim().toLowerCase()];
      if (match == null) {
        notFound.add(entry.key);
        continue;
      }

      await deductFromOrder(
        inventoryItemId: match.id,
        branchId: branchId,
        quantity: qty,
        orderId: orderId,
        menuItemName: menuItemName,
        createdBy: createdBy,
      );
    }

    return notFound;
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

  /// Roll over closing stock → next day's opening stock.
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
        // ✅ FIX: carry over the secondary unit
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
    String? menuItemName,   // ← NEW
  }) async {
    await _client.from('inventory_transactions').insert({
      'inventory_item_id': inventoryItemId,
      'branch_id': branchId,
      'transaction_type': type,
      'quantity': quantity,
      'notes': note,
      'reference_id': referenceId,
      'performed_by': createdBy,
      'menu_item_name': menuItemName,   // ← NEW: menu item name shown in history
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
              .from('menu_items')
              .update({'is_available': false})
              .eq('id', menuId.trim())
              .eq('branch_id', branchId);
        }
      }
    } catch (_) {
      // Don't crash if the menu update fails
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