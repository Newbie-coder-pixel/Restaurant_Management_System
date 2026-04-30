// lib/features/menu/providers/menu_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/menu_model.dart';
import '../presentation/services/menu_service.dart';

// ─── SERVICE PROVIDER ─────────────────────────────────────────────────────────

final menuServiceProvider = Provider<MenuService>((ref) {
  return MenuService(Supabase.instance.client);
});

// ─── FILTER STATE ─────────────────────────────────────────────────────────────

class MenuFilter {
  final String? categoryId;
  final String searchQuery;
  final bool? showAvailableOnly;
  final String? branchId;

  const MenuFilter({
    this.categoryId,
    this.searchQuery = '',
    this.showAvailableOnly,
    this.branchId,
  });

  MenuFilter copyWith({
    String? categoryId,
    String? searchQuery,
    bool? showAvailableOnly,
    String? branchId,
    bool clearCategory = false,
  }) {
    return MenuFilter(
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      searchQuery: searchQuery ?? this.searchQuery,
      showAvailableOnly: showAvailableOnly ?? this.showAvailableOnly,
      branchId: branchId ?? this.branchId,
    );
  }
}

final menuFilterProvider =
    StateProvider<MenuFilter>((ref) => const MenuFilter());

// ─── MENU NOTIFIER ────────────────────────────────────────────────────────────

class MenuNotifier extends AsyncNotifier<List<MenuItem>> {
  late MenuService _service;
  RealtimeChannel? _realtimeChannel;

  @override
  Future<List<MenuItem>> build() async {
    _service = ref.watch(menuServiceProvider);
    _setupRealtimeSubscription();
    ref.onDispose(() {
      _realtimeChannel?.unsubscribe();
    });
    return _service.fetchMenus();
  }

  void _setupRealtimeSubscription() {
    _realtimeChannel = _service.subscribeToMenuChanges(
      onInsert: (newRecord) {
        final newItem = MenuItem.fromJson(newRecord);
        state = state.whenData((items) => [...items, newItem]);
      },
      onUpdate: (updatedRecord) {
        final updatedItem = MenuItem.fromJson(updatedRecord);
        state = state.whenData((items) =>
            items.map((m) => m.id == updatedItem.id ? updatedItem : m).toList());
      },
      onDelete: (deletedRecord) {
        final deletedId = deletedRecord['id'] as String?;
        if (deletedId != null) {
          state = state.whenData(
              (items) => items.where((m) => m.id != deletedId).toList());
        }
      },
    );
  }

  // ─── ACTIONS ──────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _service.fetchMenus());
  }

  Future<bool> toggleAvailability(String id, bool currentStatus) async {
    final newStatus = !currentStatus;

    state = state.whenData((items) => items
        .map((m) => m.id == id ? m.copyWith(isAvailable: newStatus) : m)
        .toList());

    try {
      await _service.toggleAvailability(id, newStatus);
      return true;
    } catch (e) {
      // Rollback
      state = state.whenData((items) => items
          .map((m) => m.id == id ? m.copyWith(isAvailable: currentStatus) : m)
          .toList());
      return false;
    }
  }

  Future<bool> addMenu({
    required String branchId,
    required String name,
    required String? description,
    required double price,
    String? categoryId,
    dynamic imageFile,
    bool isSeasonal = false,
    int preparationTimeMinutes = 15,
  }) async {
    try {
      String? imageUrl;
      if (imageFile != null) {
        imageUrl = await _service.uploadImage(imageFile);
      }

      final item = MenuItem(
        id: '',
        branchId: branchId,
        categoryId: categoryId,
        name: name,
        description: description,
        price: price,
        imageUrl: imageUrl,
        isAvailable: true,
        isSeasonal: isSeasonal,
        preparationTimeMinutes: preparationTimeMinutes,
      );

      await _service.addMenu(item);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateMenu({
    required MenuItem item,
    dynamic newImageFile,
  }) async {
    try {
      String? imageUrl = item.imageUrl;
      if (newImageFile != null) {
        imageUrl = await _service.uploadImage(newImageFile);
      }
      await _service.updateMenu(item.copyWith(imageUrl: imageUrl));
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteMenu(String id) async {
    final item = state.valueOrNull?.firstWhere(
      (m) => m.id == id,
      orElse: () => const MenuItem(
        id: '',
        branchId: '',
        name: '',
        price: 0,
        isAvailable: true,
        isSeasonal: false,
        preparationTimeMinutes: 15,
      ),
    );

    state = state.whenData((items) => items.where((m) => m.id != id).toList());

    try {
      await _service.deleteMenu(id, imageUrl: item?.imageUrl);
      return true;
    } catch (e) {
      if (item != null && item.id.isNotEmpty) {
        state = state.whenData((items) => [...items, item]);
      }
      return false;
    }
  }
}

final menuProvider =
    AsyncNotifierProvider<MenuNotifier, List<MenuItem>>(MenuNotifier.new);

// ─── DERIVED PROVIDERS ────────────────────────────────────────────────────────

final filteredMenuProvider = Provider<AsyncValue<List<MenuItem>>>((ref) {
  final menusAsync = ref.watch(menuProvider);
  final filter = ref.watch(menuFilterProvider);

  return menusAsync.whenData((items) {
    var result = items;

    if (filter.branchId != null) {
      result = result.where((m) => m.branchId == filter.branchId).toList();
    }

    if (filter.categoryId != null) {
      result =
          result.where((m) => m.categoryId == filter.categoryId).toList();
    }

    if (filter.searchQuery.isNotEmpty) {
      final query = filter.searchQuery.toLowerCase();
      result = result
          .where((m) =>
              m.name.toLowerCase().contains(query) ||
              (m.description?.toLowerCase().contains(query) ?? false))
          .toList();
    }

    if (filter.showAvailableOnly == true) {
      result = result.where((m) => m.isAvailable).toList();
    }

    return result;
  });
});

/// Jumlah menu per categoryId.
final menuCountByCategoryProvider = Provider<Map<String?, int>>((ref) {
  final items = ref.watch(menuProvider).valueOrNull ?? [];
  final counts = <String?, int>{};
  for (final m in items) {
    counts[m.categoryId] = (counts[m.categoryId] ?? 0) + 1;
  }
  return counts;
});

// ─── CATEGORY NOTIFIER ────────────────────────────────────────────────────────

class CategoryNotifier extends FamilyAsyncNotifier<List<MenuCategory>, String> {
  late MenuService _service;

  @override
  Future<List<MenuCategory>> build(String branchId) async {
    _service = ref.watch(menuServiceProvider);
    return _service.fetchCategories(branchId: branchId);
  }

  Future<bool> addCategory(String name) async {
    final branchId = arg;
    try {
      final newCat = await _service.addCategory(branchId: branchId, name: name);
      state = state.whenData((cats) => [...cats, newCat]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteCategory(String categoryId) async {
    final prev = state.valueOrNull ?? [];
    state = state.whenData((cats) => cats.where((c) => c.id != categoryId).toList());
    try {
      await _service.deleteCategory(categoryId);
      return true;
    } catch (_) {
      state = AsyncData(prev);
      return false;
    }
  }
}

final categoryNotifierProvider =
    AsyncNotifierProviderFamily<CategoryNotifier, List<MenuCategory>, String>(
        CategoryNotifier.new);