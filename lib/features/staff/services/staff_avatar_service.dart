// lib/features/staff/services/staff_avatar_service.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StaffAvatarService {
  static final _client = Supabase.instance.client;
  static const _bucket = 'staff-avatars';

  /// Pick a photo from the gallery or camera, then upload it to Supabase Storage.
  /// Returns the new public URL, or null if cancelled / failed.
  static Future<String?> pickAndUpload({
    required BuildContext context,
    required String staffId,
    String? oldAvatarUrl,
  }) async {
    // 1. Pick a photo source
    final source = await _pickSource(context);
    if (source == null) return null;

    // 2. Get the image
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return null;

    final file = File(picked.path);
    final ext = picked.path.split('.').last.toLowerCase();
    final path = 'staff/$staffId/avatar.$ext';

    try {
      // 3. Delete the old file if it exists (to avoid piling up in storage)
      if (oldAvatarUrl != null) {
        final oldPath = _extractStoragePath(oldAvatarUrl);
        if (oldPath != null) {
          await _client.storage.from(_bucket).remove([oldPath]);
        }
      }

      // 4. Upload the new file
      await _client.storage.from(_bucket).upload(
        path,
        file,
        fileOptions: FileOptions(
          upsert: true,
          contentType: 'image/$ext',
        ),
      );

      // 5. Get the public URL
      final publicUrl = _client.storage.from(_bucket).getPublicUrl(path);

      // 6. Update the avatar_url column in the staff table
      await _client
          .from('staff')
          .update({
            'avatar_url': publicUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', staffId);

      return publicUrl;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to upload photo: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      return null;
    }
  }

  /// Remove the staff avatar (set avatar_url to null).
  static Future<bool> removeAvatar({
    required BuildContext context,
    required String staffId,
    required String avatarUrl,
  }) async {
    try {
      final path = _extractStoragePath(avatarUrl);
      if (path != null) {
        await _client.storage.from(_bucket).remove([path]);
      }
      await _client
          .from('staff')
          .update({
            'avatar_url': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', staffId);
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to remove photo: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      return false;
    }
  }

  // ── helpers ─────────────────────────────────────────────

  /// Bottom sheet to pick camera or gallery
  static Future<ImageSource?> _pickSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Choose Photo From',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.photo_library_outlined, color: Color(0xFF1976D2)),
                ),
                title: const Text('Photo Gallery',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500)),
                subtitle: const Text('Choose from existing photos',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8F5E9),
                  child: Icon(Icons.camera_alt_outlined, color: Color(0xFF388E3C)),
                ),
                title: const Text('Camera',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500)),
                subtitle: const Text('Take a new photo now',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Extract the storage path from a Supabase public URL.
  /// Example URL: https://xxx.supabase.co/storage/v1/object/public/staff-avatars/staff/abc/avatar.jpg
  /// → returns: staff/abc/avatar.jpg
  static String? _extractStoragePath(String url) {
    try {
      const marker = '/$_bucket/';
      final idx = url.indexOf(marker);
      if (idx == -1) return null;
      return url.substring(idx + marker.length);
    } catch (_) {
      return null;
    }
  }
}