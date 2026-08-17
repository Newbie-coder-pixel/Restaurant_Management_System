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
  /// Two WebKit-specific gotchas this has to work around (found via
  /// audioplayers_web's WrappedPlayer source):
  /// - `setUrl()` tears down and recreates the underlying `<audio>`
  ///   element (and its Web Audio graph) every time a *different* sound
  ///   URL is played — priming only one asset left the other three
  ///   chimes permanently unprimed on strict browsers. So this now
  ///   primes every entry in [_assetFor], not just the kitchen chime.
  /// - the shared `AudioContext` gets auto-suspended by iOS Safari
  ///   whenever the tab loses focus or the screen locks; `start()`
  ///   calls `AudioContext.resume()` on every play, which silently
  ///   fails once there's no live user gesture (i.e. exactly when a
  ///   realtime chime tries to play after the tab was backgrounded).
  ///   So this deliberately re-primes on *every* pointer-down instead
  ///   of only the first one — cheap (muted, near-instant) and it's the
  ///   only way to re-resume a context WebKit re-suspended after the
  ///   initial unlock.
  ///
  /// Call this from every pointer-down anywhere in the app (see
  /// main.dart's RestaurantApp).
  static Future<void> unlock() async {
    if (_unlocking) return;
    _unlocking = true;
    try {
      await _player.setVolume(0);
      for (final sound in NotificationSound.values) {
        await _player.play(AssetSource(_assetFor[sound]!));
        await _player.stop();
      }
      await _player.setVolume(1);
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
