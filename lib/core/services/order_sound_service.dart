// lib/core/services/order_sound_service.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the short chime used to alert staff to a new/updated order —
/// KDS's new-order banner and the global OrderNotificationOverlay both
/// call this instead of each owning their own AudioPlayer.
class OrderSoundService {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playNewOrder() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/new_order.wav'));
    } catch (e) {
      debugPrint('[OrderSoundService] play error: $e');
    }
  }
}
