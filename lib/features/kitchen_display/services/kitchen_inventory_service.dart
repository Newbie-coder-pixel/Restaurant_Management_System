// lib/features/kitchen_display/services/kitchen_inventory_service.dart
//
// Connects the Kitchen (KDS) ↔ Menu (recipes/ingredients) ↔ Inventory.
//
// When kitchen staff tap "Start Cooking" (order → preparing), this service
// will:
//   1. Fetch the recipe (menu_ingredients) for each menu item in the order.
//   2. Multiply the recipe quantity by the ordered quantity.
//   3. Deduct inventory stock for the ingredients used (matched by name,
//      since inventory is tracked daily).
//
// Designed to fail safely: if an ingredient isn't found in today's
// inventory, it's skipped (reported via [KitchenDeductionResult])
// without failing the cooking process for other items.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/menu_model.dart';
import '../../../shared/models/order_model.dart';
import '../../menu/presentation/services/menu_service.dart';
import '../../inventory/services/inventory_service.dart';

/// Summary of the stock deduction result for one order.
class KitchenDeductionResult {
  /// Names of the ingredients whose stock was successfully deducted.
  final List<String> deducted;

  /// Names of ingredients not found in this branch's inventory today
  /// (likely not registered yet / a naming mismatch).
  final List<String> notFoundInInventory;

  /// Menu items that were ordered but don't have a recipe yet (empty menu_ingredients).
  final List<String> menusWithoutRecipe;

  const KitchenDeductionResult({
    this.deducted = const [],
    this.notFoundInInventory = const [],
    this.menusWithoutRecipe = const [],
  });

  bool get hasWarnings =>
      notFoundInInventory.isNotEmpty || menusWithoutRecipe.isNotEmpty;
}

class KitchenInventoryService {
  final MenuService _menuService;
  final InventoryService _inventoryService;

  KitchenInventoryService(SupabaseClient client)
      : _menuService = MenuService(client),
        _inventoryService = InventoryService(client);

  /// Deduct inventory stock for all items in [order] per the menu recipe.
  /// Called once when the order status changes to "preparing".
  Future<KitchenDeductionResult> deductStockForOrder({
    required OrderModel order,
    String? createdBy,
  }) async {
    final branchId = order.branchId;
    final items = order.items.where((i) => i.menuItemId.isNotEmpty).toList();
    if (branchId.isEmpty || items.isEmpty) {
      return const KitchenDeductionResult();
    }

    final menuItemIds = items.map((i) => i.menuItemId).toSet().toList();

    Map<String, List<MenuIngredient>> recipes;
    try {
      recipes = await _menuService.fetchIngredientsForMenuItems(menuItemIds);
    } catch (e) {
      debugPrint('⚠️ KitchenInventoryService: failed to load menu recipes: $e');
      return const KitchenDeductionResult();
    }

    // Combine ingredient requirements across all order items (summing when
    // the same ingredient is used by more than one menu in the same order).
    final requirements = <String, double>{};
    final menusWithoutRecipe = <String>[];

    for (final item in items) {
      final recipe = recipes[item.menuItemId];
      if (recipe == null || recipe.isEmpty) {
        menusWithoutRecipe.add(item.menuItemName);
        continue;
      }
      for (final ingredient in recipe) {
        final totalQty = ingredient.quantity * item.quantity;
        if (totalQty <= 0) continue;
        requirements.update(
          ingredient.inventoryItemName,
          (existing) => existing + totalQty,
          ifAbsent: () => totalQty,
        );
      }
    }

    if (requirements.isEmpty) {
      return KitchenDeductionResult(menusWithoutRecipe: menusWithoutRecipe);
    }

    List<String> notFound = [];
    try {
      notFound = await _inventoryService.deductIngredientsForOrder(
        branchId: branchId,
        orderId: order.id,
        requirements: requirements,
        menuItemName: items.length == 1 ? items.first.menuItemName : null,
        createdBy: createdBy,
      );
    } catch (e) {
      debugPrint('⚠️ KitchenInventoryService: failed to deduct stock: $e');
    }

    final deducted = requirements.keys
        .where((name) => !notFound.contains(name))
        .toList();

    return KitchenDeductionResult(
      deducted: deducted,
      notFoundInInventory: notFound,
      menusWithoutRecipe: menusWithoutRecipe,
    );
  }
}
