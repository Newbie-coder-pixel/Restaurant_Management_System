// lib/features/menu/presentation/services/menu_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/menu_model.dart';

class MenuService {
  final SupabaseClient _client;
  static const String _itemsTable = 'menu_items';
  static const String _categoriesTable = 'menu_categories';
  static const String _bucketName = 'menu-images';

  MenuService(this._client);

  // ─── FETCH ────────────────────────────────────────────────────────────────

  /// Ambil semua menu items dari semua branch (untuk admin view global).
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
      throw MenuServiceException('Gagal memuat menu: ${e.message}');
    } catch (e) {
      throw MenuServiceException('Terjadi kesalahan tidak terduga: $e');
    }
  }

  /// Ambil semua kategori, opsional filter per branch.
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
      throw MenuServiceException('Gagal memuat kategori: ${e.message}');
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
      throw MenuServiceException('Gagal menambahkan kategori: ${e.message}');
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    try {
      await _client
          .from(_categoriesTable)
          .update({'is_active': false}).eq('id', categoryId);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Gagal menghapus kategori: ${e.message}');
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
      throw MenuServiceException('Gagal menambahkan menu: ${e.message}');
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
      throw MenuServiceException('Gagal mengupdate menu: ${e.message}');
    }
  }

  Future<void> toggleAvailability(String id, bool status) async {
    try {
      await _client.from(_itemsTable).update({
        'is_available': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Gagal mengubah status menu: ${e.message}');
    }
  }
  
  // Saat menambah stok (purchase), re-enable menu terkait
Future<void> _reEnableLinkedMenus(String inventoryItemId, String branchId) async {
  final item = await getInventoryItem(inventoryItemId);
  if (item.availableStock > 0 && item.linkedMenuIds != null) {
    final menuIds = parseMenuIds(item.linkedMenuIds!);
    for (final menuId in menuIds) {
      await _client.from('menus')
        .update({'is_available': true})
        .eq('id', menuId)
        .eq('branch_id', branchId);
    }
  }
}

  // ─── DELETE ───────────────────────────────────────────────────────────────

  Future<void> deleteMenu(String id, {String? imageUrl}) async {
    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await _deleteImageByUrl(imageUrl);
      }
      await _client.from(_itemsTable).delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Gagal menghapus menu: ${e.message}');
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
        throw const MenuServiceException('Tipe file tidak didukung');
      }

      return _client.storage.from(_bucketName).getPublicUrl(filePath);
    } on StorageException catch (e) {
      throw MenuServiceException('Gagal mengunggah gambar: ${e.message}');
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