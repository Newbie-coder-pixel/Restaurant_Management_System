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

    // Refresh token otomatis
    _messaging.onTokenRefresh.listen(_saveTokenToSupabase);

    // Handle notif saat app terbuka (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground notif: ${message.notification?.title}');
      // Nanti kita tambahkan local notification di sini
    });
  }

  static Future<void> _saveTokenToSupabase(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    await Supabase.instance.client.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': 'android',
    }, onConflict: 'user_id');
  }
}