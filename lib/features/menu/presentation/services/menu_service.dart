// lib/features/menu/presentation/services/menu_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/menu_model.dart';
// MenuIngredient & MenuIngredientDraft already exist in menu_model.dart

class MenuService {
  final SupabaseClient _client;
  static const String _itemsTable = 'menu_items';
  static const String _categoriesTable = 'menu_categories';
  static const String _bucketName = 'menu-images';
  static const String _ingredientsTable = 'menu_ingredients';

  MenuService(this._client);

  // ─── FETCH ────────────────────────────────────────────────────────────────

  /// Fetch all menu items from all branches (for the global admin view).
  Future<List<MenuItem>> fetchMenus({String? branchId}) async {
    try {
      var query = _client
          .from(_itemsTable)
          .select()
          .order('name', ascending: true);

      if (branchId != null) {
        query = _client
            .from(_itemsTable)
            .select()
            .eq('branch_id', branchId)
            .order('name', ascending: true);
      }

      final response = await query;
      return (response as List<dynamic>)
          .map((item) => MenuItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to load menu: ${e.message}');
    } catch (e) {
      throw MenuServiceException('An unexpected error occurred: $e');
    }
  }

  /// Fetch all categories, optionally filtered by branch.
  Future<List<MenuCategory>> fetchCategories({String? branchId}) async {
    try {
      var query = _client
          .from(_categoriesTable)
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      if (branchId != null) {
        query = _client
            .from(_categoriesTable)
            .select()
            .eq('branch_id', branchId)
            .eq('is_active', true)
            .order('sort_order', ascending: true);
      }

      final response = await query;
      return (response as List<dynamic>)
          .map((item) => MenuCategory.fromJson(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to load categories: ${e.message}');
    }
  }

  // ─── CATEGORY CRUD ────────────────────────────────────────────────────────

  Future<MenuCategory> addCategory({
    required String branchId,
    required String name,
  }) async {
    try {
      final existing = await _client
          .from(_categoriesTable)
          .select('sort_order')
          .eq('branch_id', branchId)
          .order('sort_order', ascending: false)
          .limit(1);

      final nextOrder = existing.isEmpty
          ? 0
          : ((existing.first['sort_order'] as int?) ?? 0) + 1;

      final response = await _client
          .from(_categoriesTable)
          .insert({
            'branch_id': branchId,
            'name': name.trim(),
            'is_active': true,
            'sort_order': nextOrder,
          })
          .select()
          .single();

      return MenuCategory.fromJson(response);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to add category: ${e.message}');
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    try {
      await _client
          .from(_categoriesTable)
          .update({'is_active': false}).eq('id', categoryId);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to delete category: ${e.message}');
    }
  }

  // ─── CREATE ───────────────────────────────────────────────────────────────

  Future<MenuItem> addMenu(MenuItem item) async {
    try {
      final response = await _client
          .from(_itemsTable)
          .insert(item.toInsertMap())
          .select()
          .single();

      return MenuItem.fromJson(response);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to add menu item: ${e.message}');
    }
  }

  // ─── INGREDIENTS ──────────────────────────────────────────────────────────

  /// Save the list of ingredients for one menu item to the
  /// `menu_ingredients` table. Called after [addMenu] succeeds and the
  /// menuItemId is known.
  ///
  /// Note: this method performs a batch insert. If ingredients is empty,
  /// the method returns immediately without doing anything.
  Future<void> saveIngredients({
    required String menuItemId,
    required List<MenuIngredientDraft> drafts,
  }) async {
    if (drafts.isEmpty) return;

    try {
      final rows = drafts
          .map((d) => d.toIngredient(menuItemId: menuItemId).toInsertMap())
          .toList();

      await _client.from(_ingredientsTable).insert(rows);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to save ingredients: ${e.message}');
    }
  }

  /// Fetch all ingredients for one menu item by [menuItemId].
  /// Returns an empty list if no ingredients are registered.
  Future<List<MenuIngredient>> fetchIngredients(String menuItemId) async {
    try {
      final response = await _client
          .from(_ingredientsTable)
          .select()
          .eq('menu_item_id', menuItemId)
          .order('created_at', ascending: true);

      return (response as List<dynamic>)
          .map((row) => MenuIngredient.fromJson(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to load ingredients: ${e.message}');
    }
  }

  /// Fetch ingredients for MULTIPLE menu items at once (batch), grouped by
  /// menuItemId. Used when the kitchen starts cooking an order (KDS) or
  /// when recalculating COGS, so we don't query item-by-item.
  Future<Map<String, List<MenuIngredient>>> fetchIngredientsForMenuItems(
      List<String> menuItemIds) async {
    if (menuItemIds.isEmpty) return {};
    try {
      final response = await _client
          .from(_ingredientsTable)
          .select()
          .inFilter('menu_item_id', menuItemIds);

      final result = <String, List<MenuIngredient>>{};
      for (final row in (response as List<dynamic>)) {
        final ingredient = MenuIngredient.fromJson(row as Map<String, dynamic>);
        result.putIfAbsent(ingredient.menuItemId, () => []).add(ingredient);
      }
      return result;
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to load menu recipe: ${e.message}');
    }
  }

  /// Delete all ingredients for one menu item.
  /// Usually doesn't need to be called manually since the table already
  /// uses ON DELETE CASCADE from menu_items. But it's available if needed
  /// (e.g. when updating ingredients: delete old ones, insert new ones).
  Future<void> deleteIngredients(String menuItemId) async {
    try {
      await _client
          .from(_ingredientsTable)
          .delete()
          .eq('menu_item_id', menuItemId);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to delete ingredients: ${e.message}');
    }
  }

  /// Update ingredients for one menu item:
  /// delete all the old ones then insert the new ones.
  /// Use this when editing a menu item and the ingredient list changes.
  Future<void> updateIngredients({
    required String menuItemId,
    required List<MenuIngredientDraft> drafts,
  }) async {
    try {
      await deleteIngredients(menuItemId);
      await saveIngredients(menuItemId: menuItemId, drafts: drafts);
    } on MenuServiceException {
      rethrow;
    }
  }

  // ─── UPDATE ───────────────────────────────────────────────────────────────

  Future<MenuItem> updateMenu(MenuItem item) async {
    try {
      final response = await _client
          .from(_itemsTable)
          .update(item.toInsertMap())
          .eq('id', item.id)
          .select()
          .single();

      return MenuItem.fromJson(response);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to update menu item: ${e.message}');
    }
  }

  Future<void> toggleAvailability(String id, bool status) async {
    try {
      await _client.from(_itemsTable).update({
        'is_available': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to change menu status: ${e.message}');
    }
  }

  // ─── Re-enable menus linked to an inventory item ──────────────────────────
  // NOTE: This logic was moved to InventoryService because it needs access
  // to inventory data. Called from InventoryService when stock increases.

  /// Re-enable menu items linked to [inventoryItemId] if stock > 0.
  /// Called from InventoryService after a purchase/restock.
  Future<void> reEnableLinkedMenus(
      List<String> menuIds, String branchId) async {
    try {
      for (final menuId in menuIds) {
        await _client
            .from(_itemsTable)
            .update({
              'is_available': true,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', menuId)
            .eq('branch_id', branchId);
      }
    } on PostgrestException catch (e) {
      throw MenuServiceException(
          'Failed to re-enable linked menu items: ${e.message}');
    }
  }

  // ─── DELETE ───────────────────────────────────────────────────────────────

  Future<void> deleteMenu(String id, {String? imageUrl}) async {
    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await _deleteImageByUrl(imageUrl);
      }
      // Ingredients will be deleted automatically via ON DELETE CASCADE,
      // but we delete them explicitly to make sure there's no orphan data.
      await deleteIngredients(id);
      await _client.from(_itemsTable).delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Failed to delete menu item: ${e.message}');
    }
  }

  // ─── STORAGE ──────────────────────────────────────────────────────────────

  Future<String> uploadImage(dynamic image) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_menu_image';
      final filePath = 'public/$fileName';

      if (image is File) {
        await _client.storage.from(_bucketName).upload(
              filePath,
              image,
              fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
            );
      } else if (image is Uint8List) {
        await _client.storage.from(_bucketName).uploadBinary(
              filePath,
              image,
              fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
            );
      } else {
        throw const MenuServiceException('Unsupported file type');
      }

      return _client.storage.from(_bucketName).getPublicUrl(filePath);
    } on StorageException catch (e) {
      throw MenuServiceException('Failed to upload image: ${e.message}');
    }
  }

  Future<void> _deleteImageByUrl(String imageUrl) async {
    try {
      final uri = Uri.parse(imageUrl);
      final segments = uri.pathSegments;
      final bucketIndex = segments.indexOf(_bucketName);
      if (bucketIndex != -1 && bucketIndex + 1 < segments.length) {
        final filePath = segments.sublist(bucketIndex + 1).join('/');
        await _client.storage.from(_bucketName).remove([filePath]);
      }
    } catch (_) {}
  }

  // ─── REALTIME ─────────────────────────────────────────────────────────────

  RealtimeChannel subscribeToMenuChanges({
    required void Function(Map<String, dynamic>) onInsert,
    required void Function(Map<String, dynamic>) onUpdate,
    required void Function(Map<String, dynamic>) onDelete,
  }) {
    return _client
        .channel('menu_items_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _itemsTable,
          callback: (payload) => onInsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: _itemsTable,
          callback: (payload) => onUpdate(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: _itemsTable,
          callback: (payload) => onDelete(payload.oldRecord),
        )
        .subscribe();
  }
}

// ─── EXCEPTION ────────────────────────────────────────────────────────────────

class MenuServiceException implements Exception {
  final String message;
  const MenuServiceException(this.message);

  @override
  String toString() => 'MenuServiceException: $message';
}