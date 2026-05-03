// lib/core/services/notification_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    // Minta izin notifikasi
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Ambil token dan simpan ke Supabase
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToSupabase(token);
    }

    // Refresh token otomatis — simpan ulang jika token berubah
    _messaging.onTokenRefresh.listen(_saveTokenToSupabase);

    // Handle notif saat app terbuka (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Foreground notif: ${message.notification?.title}');
    });
  }

  static Future<void> _saveTokenToSupabase(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Detect platform secara otomatis
    final platform = _detectPlatform();

    try {
      await Supabase.instance.client.from('device_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': platform,
          'created_at': DateTime.now().toIso8601String(),
        },
        // Conflict per user_id + platform supaya 1 user bisa punya
        // token di beberapa device (Android + iOS + Web sekaligus)
        onConflict: 'user_id,platform',
      );
      debugPrint('[FCM] Token saved — user: $userId platform: $platform');
    } catch (e) {
      debugPrint('[FCM] Save token error: $e');
    }
  }

  static String _detectPlatform() {
    if (kIsWeb) return 'web';
    // defaultTargetPlatform hanya tersedia di non-web
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      default:
        return 'other';
    }
  }

  /// Hapus token saat user logout — supaya tidak terima notif setelah logout
  static Future<void> removeToken() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final platform = _detectPlatform();
    try {
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('platform', platform);
      debugPrint('[FCM] Token removed — user: $userId platform: $platform');
    } catch (e) {
      debugPrint('[FCM] Remove token error: $e');
    }
  }
}