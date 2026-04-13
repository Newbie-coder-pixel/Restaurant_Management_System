// lib/features/menu/services/menu_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/menu_model.dart';

class MenuService {
  final SupabaseClient _client;
  static const String _tableName = 'menus';
  static const String _bucketName = 'menu-images';

  MenuService(this._client);

  // ─── FETCH ────────────────────────────────────────────────────────────────

  /// Ambil semua menu, diurutkan berdasarkan kategori lalu nama.
  Future<List<Menu>> fetchMenus() async {
    try {
      final response = await _client
          .from(_tableName)
          .select()
          .order('category', ascending: true)
          .order('name', ascending: true);

      return (response as List<dynamic>)
          .map((item) => Menu.fromMap(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw MenuServiceException('Gagal memuat menu: ${e.message}');
    } catch (e) {
      throw MenuServiceException('Terjadi kesalahan tidak terduga: $e');
    }
  }

  // ─── CREATE ───────────────────────────────────────────────────────────────

  Future<Menu> addMenu(Menu menu) async {
    try {
      final response = await _client
          .from(_tableName)
          .insert(menu.toInsertMap())
          .select()
          .single();

      return Menu.fromMap(response);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Gagal menambahkan menu: ${e.message}');
    }
  }

  // ─── UPDATE ───────────────────────────────────────────────────────────────

  Future<Menu> updateMenu(Menu menu) async {
    try {
      final response = await _client
          .from(_tableName)
          .update(menu.toInsertMap())
          .eq('id', menu.id)
          .select()
          .single();

      return Menu.fromMap(response);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Gagal mengupdate menu: ${e.message}');
    }
  }

  Future<void> toggleAvailability(String id, bool status) async {
    try {
      final newStatus =
          status ? MenuStatus.available.name : MenuStatus.outOfStock.name;

      await _client.from(_tableName).update({
        'is_available': status,
        'status': newStatus,
      }).eq('id', id);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Gagal mengubah status menu: ${e.message}');
    }
  }

  // ─── DELETE ───────────────────────────────────────────────────────────────

  Future<void> deleteMenu(String id, {String? imageUrl}) async {
    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await _deleteImageByUrl(imageUrl);
      }
      await _client.from(_tableName).delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw MenuServiceException('Gagal menghapus menu: ${e.message}');
    }
  }

  // ─── STORAGE ──────────────────────────────────────────────────────────────

  /// Upload gambar menu. Mendukung File (mobile) dan Uint8List (web/file_picker).
  Future<String> uploadImage(dynamic image) async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_menu_image';
      final filePath = 'public/$fileName';

      if (image is File) {
        // Mobile — dart:io File
        await _client.storage.from(_bucketName).upload(
              filePath,
              image,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: false,
              ),
            );
      } else if (image is Uint8List) {
        // Web / file_picker withData: true
        await _client.storage.from(_bucketName).uploadBinary(
              filePath,
              image,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: false,
              ),
            );
      } else {
        throw MenuServiceException('Tipe file tidak didukung');
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
    } catch (_) {
      // Tidak perlu throw — gambar mungkin sudah tidak ada
    }
  }

  // ─── REALTIME ─────────────────────────────────────────────────────────────

  RealtimeChannel subscribeToMenuChanges({
    required void Function(Map<String, dynamic>) onInsert,
    required void Function(Map<String, dynamic>) onUpdate,
    required void Function(Map<String, dynamic>) onDelete,
  }) {
    return _client
        .channel('menu_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _tableName,
          callback: (payload) => onInsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: _tableName,
          callback: (payload) => onUpdate(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: _tableName,
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