// lib/shared/services/customer_sound_preference.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/order_sound_service.dart';

/// Customer/QR-only opt-in for order-progress chimes, kept separate from
/// OrderSoundService's browser-autoplay unlock mechanics (which only make
/// audio *technically possible*; this tracks whether the diner actually
/// *wants* it — the "weather app asking for notification permission"
/// pattern OrderNotificationOverlay's sound prompt implements). The staff
/// app is entirely unaffected: every staff member always gets sound, no
/// prompt, no opt-out — this preference is only ever read for
/// appMode == 'customer'/'qr'.
///
/// Stored in shared_preferences (localStorage on web), so it persists per
/// browser/device across an anonymous QR session's page reloads without
/// needing any user_id — same trade-off notification_bell.dart's "last
/// seen" timestamp already makes for the staff side.
class CustomerSoundPreference {
  static const _prefsKey = 'customer_sound_enabled';

  /// null = never decided on this device yet (prompt should be shown).
  /// true/false = diner already made a choice; don't ask again.
  static final ValueNotifier<bool?> value = ValueNotifier<bool?>(null);
  static bool _loaded = false;

  /// Must be awaited before [value] is trusted — until this completes,
  /// null just means "haven't read shared_preferences yet", not "never
  /// asked". Safe to call repeatedly; only reads storage once.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_prefsKey)) {
      value.value = prefs.getBool(_prefsKey);
    }
    _loaded = true;
  }

  static Future<void> setEnabled(bool enabled) async {
    value.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
    // Turning it on IS the user gesture (a button tap) audio autoplay
    // policy requires — prime it right away instead of waiting for the
    // next pointer-down.
    if (enabled) await OrderSoundService.unlock();
  }
}
