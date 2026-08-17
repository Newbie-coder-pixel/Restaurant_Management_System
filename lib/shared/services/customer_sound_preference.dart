// lib/shared/services/customer_sound_preference.dart
import 'package:flutter/foundation.dart';
import '../../core/services/order_sound_service.dart';

/// Customer/QR-only opt-in for order-progress chimes, kept separate from
/// OrderSoundService's browser-autoplay unlock mechanics (which only make
/// audio *technically possible*; this tracks whether the diner actually
/// *consented* to it — the "weather app asking for notification
/// permission" pattern OrderNotificationOverlay's sound prompt
/// implements). The staff app is entirely unaffected: every staff member
/// always gets sound, no prompt, no opt-out.
///
/// Deliberately **not** persisted to shared_preferences/localStorage:
/// consent here is scoped to the single order currently being tracked,
/// not to the device. Reloading the tracker, or tracking a different
/// order, always asks again — even on a device that said yes before —
/// and consent is explicitly revoked the moment that order's payment
/// completes, rather than lingering as a standing grant. Pure in-memory
/// state is what makes both of those true for free: a full page reload
/// already wipes it, and [revokeForOrder] wipes it early on payment.
class CustomerSoundPreference {
  static String? _orderId;
  static bool? _enabledForOrder;

  /// null = this order hasn't been decided on yet (prompt should be
  /// shown) — including the very first time, and any time [orderId]
  /// differs from whichever order was last decided on.
  static bool? valueFor(String orderId) {
    if (_orderId != orderId) return null;
    return _enabledForOrder;
  }

  static void setEnabled(String orderId, bool enabled) {
    _orderId = orderId;
    _enabledForOrder = enabled;
    _bump();
    // Granting IS the user gesture (a button tap) audio autoplay policy
    // requires — prime it right away instead of waiting for the next
    // pointer-down.
    if (enabled) OrderSoundService.unlock();
  }

  /// Called once an order's payment completes — consent doesn't carry
  /// past the transaction it was given for.
  static void revokeForOrder(String orderId) {
    if (_orderId == orderId) {
      _enabledForOrder = false;
      _bump();
    }
  }

  /// So header toggle icons can react to a decision made elsewhere (the
  /// permission dialog) without each screen owning its own state.
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  static ValueListenable<int> get revision => _revision;

  static void _bump() => _revision.value++;
}
