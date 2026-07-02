// lib/features/kitchen_display/services/kitchen_inventory_service.dart
//
// Menghubungkan Dapur (KDS) ↔ Menu (resep/ingredients) ↔ Inventory.
//
// Saat staff dapur menekan "Mulai Masak" (order → preparing), service ini
// akan:
//   1. Ambil resep (menu_ingredients) untuk setiap menu item dalam order.
//   2. Kalikan quantity resep dengan quantity yang dipesan.
//   3. Potong stok inventory sesuai bahan yang terpakai (dicocokkan per nama,
//      karena inventory bersifat harian).
//
// Dirancang untuk gagal secara aman: kalau satu bahan tidak ditemukan di
// inventory hari ini, bahan itu dilewati (dilaporkan lewat [KitchenDeductionResult])
// tanpa menggagalkan proses masak untuk item lain.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/menu_model.dart';
import '../../../shared/models/order_model.dart';
import '../../menu/presentation/services/menu_service.dart';
import '../../inventory/services/inventory_service.dart';

/// Ringkasan hasil pemotongan stok untuk satu order.
class KitchenDeductionResult {
  /// Nama bahan baku yang berhasil dipotong stoknya.
  final List<String> deducted;

  /// Nama bahan baku yang tidak ditemukan di inventory cabang ini hari ini
  /// (kemungkinan belum didaftarkan / salah penamaan).
  final List<String> notFoundInInventory;

  /// Menu item yang dipesan tapi belum punya resep (menu_ingredients kosong).
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

  /// Potong stok inventory untuk semua item dalam [order] sesuai resep menu.
  /// Dipanggil sekali saat order pindah status ke "preparing".
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
      debugPrint('⚠️ KitchenInventoryService: gagal memuat resep menu: $e');
      return const KitchenDeductionResult();
    }

    // Gabungkan kebutuhan bahan dari semua item order (menjumlahkan bila ada
    // bahan yang sama dipakai lebih dari satu menu dalam order yang sama).
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
      debugPrint('⚠️ KitchenInventoryService: gagal memotong stok: $e');
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
