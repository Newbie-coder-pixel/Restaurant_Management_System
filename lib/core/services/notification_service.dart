// lib/core/services/notification_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _listenersRegistered = false;
  static bool _localNotifsInitialized = false;

  /// Returns true if the token was successfully saved to Supabase.
  static Future<bool> initialize() async {
    // Request notification permission
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get the token and save it to Supabase
    final token = await _messaging.getToken();
    final saved = token != null && await _saveTokenToSupabase(token);

    // Token refresh & foreground notification listeners only need to be registered once
    // (previously re-registered on every initialize() call, stacking up listeners)
    if (!_listenersRegistered) {
      _listenersRegistered = true;

      // Automatic token refresh — save again if the token changes
      _messaging.onTokenRefresh.listen(_saveTokenToSupabase);

      // Handle notifications while the app is open (foreground) — FCM does
      // not auto-display a system notification in this case, so show one
      // ourselves via flutter_local_notifications (previously a no-op:
      // this only debugPrint'd the title and nothing was visible to the
      // user while the app was focused).
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM] Foreground notif: ${message.notification?.title}');
        _showLocalNotification(message);
      });
    }

    return saved;
  }

  static Future<void> _ensureLocalNotificationsInitialized() async {
    if (_localNotifsInitialized || kIsWeb) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      macOS: iosInit,
    );
    await _localNotifications.initialize(settings);
    _localNotifsInitialized = true;
  }

  /// Shows a native notification banner for a foregrounded FCM message —
  /// web isn't supported by flutter_local_notifications, but the browser
  /// itself already surfaces FCM notifications when the tab isn't focused,
  /// so this only needs to cover mobile/desktop.
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    if (kIsWeb) return;
    final notification = message.notification;
    if (notification == null) return;

    try {
      await _ensureLocalNotificationsInitialized();
      const androidDetails = AndroidNotificationDetails(
        'order_events_channel',
        'Order Updates',
        channelDescription:
            'Order status, payment, and bill-request updates',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      );
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        details,
      );
    } catch (e) {
      debugPrint('[FCM] Local notification error: $e');
    }
  }

  static Future<bool> _saveTokenToSupabase(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    // Automatically detect the platform
    final platform = _detectPlatform();

    try {
      await Supabase.instance.client.from('device_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toIso8601String(),
        },
        // Conflict per user_id + platform so that 1 user can have
        // tokens on multiple devices (Android + iOS + Web at once)
        onConflict: 'user_id,platform',
      );
      debugPrint('[FCM] Token saved — user: $userId platform: $platform');
      return true;
    } catch (e) {
      debugPrint('[FCM] Save token error: $e');
      return false;
    }
  }

  static String _detectPlatform() {
    if (kIsWeb) return 'web';
    // defaultTargetPlatform is only available on non-web
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

  /// Remove the token on user logout — so notifications aren't received after logout
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