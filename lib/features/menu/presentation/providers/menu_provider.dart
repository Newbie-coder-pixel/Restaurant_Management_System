// lib/features/menu/providers/menu_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/menu_model.dart';
import '../services/menu_service.dart';

// ─── SERVICE PROVIDER ─────────────────────────────────────────────────────────

final menuServiceProvider = Provider<MenuService>((ref) {
  return MenuService(Supabase.instance.client);
});

// ─── FILTER STATE ─────────────────────────────────────────────────────────────

class MenuFilter {
  final MenuCategory? category;
  final String searchQuery;
  final bool? showAvailableOnly;

  const MenuFilter({
    this.category,
    this.searchQuery = '',
    this.showAvailableOnly,
  });

  MenuFilter copyWith({
    MenuCategory? category,
    String? searchQuery,
    bool? showAvailableOnly,
    bool clearCategory = false,
  }) {
    return MenuFilter(
      category: clearCategory ? null : (category ?? this.category),
      searchQuery: searchQuery ?? this.searchQuery,
      showAvailableOnly: showAvailableOnly ?? this.showAvailableOnly,
    );
  }
}

final menuFilterProvider =
    StateProvider<MenuFilter>((ref) => const MenuFilter());

// ─── MENU NOTIFIER ────────────────────────────────────────────────────────────

class MenuNotifier extends AsyncNotifier<List<Menu>> {
  late MenuService _service;
  RealtimeChannel? _realtimeChannel;

  @override
  Future<List<Menu>> build() async {
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
        final newMenu = Menu.fromMap(newRecord);
        state = state.whenData((menus) => [...menus, newMenu]);
      },
      onUpdate: (updatedRecord) {
        final updatedMenu = Menu.fromMap(updatedRecord);
        state = state.whenData((menus) => menus
            .map((m) => m.id == updatedMenu.id ? updatedMenu : m)
            .toList());
      },
      onDelete: (deletedRecord) {
        final deletedId = deletedRecord['id'] as String?;
        if (deletedId != null) {
          state = state.whenData(
              (menus) => menus.where((m) => m.id != deletedId).toList());
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

    // Optimistic update
    state = state.whenData((menus) => menus
        .map((m) => m.id == id
            ? m.copyWith(
                isAvailable: newStatus,
                status:
                    newStatus ? MenuStatus.available : MenuStatus.outOfStock,
              )
            : m)
        .toList());

    try {
      await _service.toggleAvailability(id, newStatus);
      return true;
    } catch (e) {
      // Rollback on error
      state = state.whenData((menus) => menus
          .map((m) => m.id == id
              ? m.copyWith(
                  isAvailable: currentStatus,
                  status: currentStatus
                      ? MenuStatus.available
                      : MenuStatus.outOfStock,
                )
              : m)
          .toList());
      return false;
    }
  }

  Future<bool> addMenu({
    required String name,
    required String description,
    required double price,
    required MenuCategory category,
    dynamic imageFile, // File? — dynamic agar kompatibel web & mobile
  }) async {
    try {
      String? imageUrl;
      if (imageFile != null) {
        imageUrl = await _service.uploadImage(imageFile);
      }

      final menu = Menu(
        id: '',
        name: name,
        description: description,
        price: price,
        imageUrl: imageUrl,
        category: category,
        isAvailable: true,
        status: MenuStatus.available,
      );

      await _service.addMenu(menu);
      // Realtime akan handle update state otomatis
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateMenu({
    required Menu menu,
    dynamic newImageFile, // File? — dynamic agar kompatibel web & mobile
  }) async {
    try {
      String? imageUrl = menu.imageUrl;
      if (newImageFile != null) {
        imageUrl = await _service.uploadImage(newImageFile);
      }

      final updatedMenu = menu.copyWith(imageUrl: imageUrl);
      await _service.updateMenu(updatedMenu);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteMenu(String id) async {
    final menu = state.valueOrNull?.firstWhere(
      (m) => m.id == id,
      orElse: () => Menu(
        id: '',
        name: '',
        description: '',
        price: 0,
        category: MenuCategory.food,
        isAvailable: true,
      ),
    );

    // Optimistic remove
    state =
        state.whenData((menus) => menus.where((m) => m.id != id).toList());

    try {
      await _service.deleteMenu(id, imageUrl: menu?.imageUrl);
      return true;
    } catch (e) {
      // Rollback
      if (menu != null && menu.id.isNotEmpty) {
        state = state.whenData((menus) => [...menus, menu]);
      }
      return false;
    }
  }
}

final menuProvider =
    AsyncNotifierProvider<MenuNotifier, List<Menu>>(MenuNotifier.new);

// ─── DERIVED PROVIDERS ────────────────────────────────────────────────────────

/// Menu yang sudah difilter berdasarkan kategori, search query, dan availabilitas.
final filteredMenuProvider = Provider<AsyncValue<List<Menu>>>((ref) {
  final menusAsync = ref.watch(menuProvider);
  final filter = ref.watch(menuFilterProvider);

  return menusAsync.whenData((menus) {
    var result = menus;

    if (filter.category != null) {
      result = result.where((m) => m.category == filter.category).toList();
    }

    if (filter.searchQuery.isNotEmpty) {
      final query = filter.searchQuery.toLowerCase();
      result = result
          .where((m) =>
              m.name.toLowerCase().contains(query) ||
              m.description.toLowerCase().contains(query))
          .toList();
    }

    if (filter.showAvailableOnly == true) {
      result = result.where((m) => m.isAvailable).toList();
    }

    return result;
  });
});

/// Jumlah menu per kategori (dari data mentah, bukan filtered).
final menuCountByCategoryProvider =
    Provider<Map<MenuCategory, int>>((ref) {
  final menus = ref.watch(menuProvider).valueOrNull ?? [];
  final counts = <MenuCategory, int>{};
  for (final m in menus) {
    counts[m.category] = (counts[m.category] ?? 0) + 1;
  }
  return counts;
}); 