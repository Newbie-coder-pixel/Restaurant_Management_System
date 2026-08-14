// lib/core/services/order_sound_service.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Which chime to play — lets staff tell notification categories apart by
/// ear without looking at the screen (e.g. a kitchen chime vs. a
/// "customer needs help at their table" call are very different levels of
/// urgency). See StaffNotification's factories for the category→sound
/// mapping.
enum NotificationSound { kitchen, service, payment, table }

const _assetFor = {
  NotificationSound.kitchen: 'sounds/new_order.wav',
  NotificationSound.service: 'sounds/service_update.wav',
  NotificationSound.payment: 'sounds/payment_update.wav',
  NotificationSound.table: 'sounds/table_call.wav',
};

/// Plays the chime used to alert staff to order/table updates — KDS's
/// new-order banner and the global OrderNotificationOverlay both call this
/// instead of each owning their own AudioPlayer.
class OrderSoundService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _unlocked = false;
  static bool _unlocking = false;

  /// Primes the shared player inside a real user-gesture call stack.
  /// Browsers (Safari/WebKit strictly, Chrome/Firefox more leniently once
  /// a site has no "media engagement" history yet) reject any
  /// `<audio>.play()` that isn't triggered directly by a user
  /// interaction — and the play() call in [play] below always happens
  /// asynchronously, in response to a realtime event arriving over a
  /// WebSocket, which is never inside a user gesture. Without this, the
  /// very first chime (and on strict browsers, every chime) silently
  /// fails with a NotAllowedError that nothing in the UI surfaces.
  ///
  /// Call this from the first pointer-down anywhere in the app (see
  /// main.dart's RestaurantApp) — safe to call repeatedly, it only
  /// actually unlocks once per page session. Only needs to prime one
  /// asset — once the browser has granted audio playback for this page,
  /// every asset through the same AudioPlayer plays freely.
  static Future<void> unlock() async {
    if (_unlocked || _unlocking) return;
    _unlocking = true;
    try {
      await _player.setVolume(0);
      await _player.play(AssetSource(_assetFor[NotificationSound.kitchen]!));
      await _player.stop();
      await _player.setVolume(1);
      _unlocked = true;
    } catch (e) {
      debugPrint('[OrderSoundService] unlock error: $e');
    } finally {
      _unlocking = false;
    }
  }

  static Future<void> play(NotificationSound sound) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(_assetFor[sound]!));
    } catch (e) {
      debugPrint('[OrderSoundService] play error: $e');
    }
  }
}
