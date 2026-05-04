// lib/features/inventory/providers/inventory_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/inventory_item.dart';
import '../services/inventory_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/supabase_client.dart';

// ─── SERVICE PROVIDER ─────────────────────────────────────────────────────────

final inventoryServiceProvider = Provider<InventoryService>((ref) {
  return InventoryService(supabase);
});

// ─── DATE PROVIDER (untuk filter tanggal) ────────────────────────────────────

final inventorySelectedDateProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

// ─── FILTER PROVIDER ─────────────────────────────────────────────────────────

class InventoryFilter {
  final String searchQuery;
  final String? category;
  final bool? showLowStockOnly;

  const InventoryFilter({
    this.searchQuery = '',
    this.category,
    this.showLowStockOnly,
  });

  InventoryFilter copyWith({
    String? searchQuery,
    String? category,
    bool? showLowStockOnly,
  }) {
    return InventoryFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      category: category ?? this.category,
      showLowStockOnly: showLowStockOnly ?? this.showLowStockOnly,
    );
  }
}

final inventoryFilterProvider =
    StateProvider<InventoryFilter>((ref) => const InventoryFilter());

// ─── MAIN INVENTORY PROVIDER (Stream) ────────────────────────────────────────

final inventoryStreamProvider =
    StreamProvider.family<List<InventoryItem>, String>((ref, branchId) {
  final service = ref.watch(inventoryServiceProvider);
  final date = ref.watch(inventorySelectedDateProvider);

  return service.streamInventoryItems(branchId: branchId, date: date);
});

// ─── FILTERED INVENTORY ───────────────────────────────────────────────────────

final filteredInventoryProvider =
    Provider.family<AsyncValue<List<InventoryItem>>, String>((ref, branchId) {
  final inventoryAsync = ref.watch(inventoryStreamProvider(branchId));
  final filter = ref.watch(inventoryFilterProvider);

  return inventoryAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
    data: (items) {
      var filtered = items;

      if (filter.searchQuery.isNotEmpty) {
        final q = filter.searchQuery.toLowerCase();
        filtered = filtered
            .where((i) =>
                i.name.toLowerCase().contains(q) ||
                i.category.toLowerCase().contains(q))
            .toList();
      }

      if (filter.category != null) {
        filtered =
            filtered.where((i) => i.category == filter.category).toList();
      }

      if (filter.showLowStockOnly == true) {
        filtered =
            filtered.where((i) => i.isLowStock || i.isOutOfStock).toList();
      }

      return AsyncValue.data(filtered);
    },
  );
});

// ─── CATEGORIES PROVIDER ──────────────────────────────────────────────────────

final inventoryCategoriesProvider =
    Provider.family<List<String>, String>((ref, branchId) {
  final itemsAsync = ref.watch(inventoryStreamProvider(branchId));
  final items = itemsAsync.valueOrNull ?? [];
  final categories = items.map((i) => i.category).toSet().toList()..sort();
  return categories;
});

// ─── SUMMARY PROVIDER ─────────────────────────────────────────────────────────

final inventorySummaryProvider =
    Provider.family<InventoryDailySummary?, String>((ref, branchId) {
  final itemsAsync = ref.watch(inventoryStreamProvider(branchId));
  final items = itemsAsync.valueOrNull ?? [];
  if (items.isEmpty) return null;

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
    date: DateTime.now(),
    totalItems: items.length,
    lowStockItems: lowStock,
    outOfStockItems: outOfStock,
    totalInventoryValue: totalValue,
    totalUsedValue: totalUsed,
    totalWasteValue: totalWaste,
  );
});

// ─── LOW STOCK ALERT COUNT (untuk badge notifikasi) ───────────────────────────

final lowStockCountProvider = Provider.family<int, String>((ref, branchId) {
  final summary = ref.watch(inventorySummaryProvider(branchId));
  return (summary?.lowStockItems ?? 0) + (summary?.outOfStockItems ?? 0);
});

// ─── INVENTORY NOTIFIER (untuk operasi CRUD) ──────────────────────────────────

class InventoryNotifier extends AsyncNotifier<List<InventoryItem>> {
  late InventoryService _service;
  late String _branchId;

  @override
  Future<List<InventoryItem>> build() async {
    _service = ref.watch(inventoryServiceProvider);
    _branchId = ref.watch(currentBranchIdProvider) ?? '';
    if (_branchId.isEmpty) return [];
    return _service.fetchInventoryItems(branchId: _branchId);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => _service.fetchInventoryItems(branchId: _branchId));
  }

  Future<void> addItem(InventoryItem item) async {
    await AsyncValue.guard(() => _service.addInventoryItem(item));
    refresh();
  }

  Future<void> updateItem(InventoryItem item) async {
    await AsyncValue.guard(() => _service.updateInventoryItem(item));
    refresh();
  }

  Future<void> recordPurchase({
    required String itemId,
    required double quantity,
    String? note,
  }) async {
    final userId = ref.read(currentUserProvider)?.id;
    await _service.recordPurchase(
      inventoryItemId: itemId,
      branchId: _branchId,
      quantity: quantity,
      note: note,
      createdBy: userId,
    );
    refresh();
  }

  Future<void> recordWaste({
    required String itemId,
    required double quantity,
    String? note,
  }) async {
    final userId = ref.read(currentUserProvider)?.id;
    await _service.recordWaste(
      inventoryItemId: itemId,
      branchId: _branchId,
      quantity: quantity,
      note: note,
      createdBy: userId,
    );
    refresh();
  }

  Future<void> adjustStock({
    required String itemId,
    required double adjustmentQty,
    required String reason,
  }) async {
    final userId = ref.read(currentUserProvider)?.id;
    await _service.adjustStock(
      inventoryItemId: itemId,
      branchId: _branchId,
      adjustmentQty: adjustmentQty,
      reason: reason,
      createdBy: userId,
    );
    refresh();
  }

  Future<void> rolloverDaily() async {
    await _service.rolloverDailyStock(_branchId);
    refresh();
  }
}

final inventoryNotifierProvider =
    AsyncNotifierProvider<InventoryNotifier, List<InventoryItem>>(
  InventoryNotifier.new,
);

// ─── TRANSACTIONS PROVIDER ────────────────────────────────────────────────────

final inventoryTransactionsProvider = FutureProvider.family<
    List<InventoryTransaction>, String>((ref, inventoryItemId) async {
  final service = ref.watch(inventoryServiceProvider);
  return service.fetchTransactions(inventoryItemId: inventoryItemId);
});
