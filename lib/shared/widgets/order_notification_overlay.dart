// lib/shared/widgets/order_notification_overlay.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/services/order_sound_service.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/customer/providers/active_orders_provider.dart';
import '../models/order_event_model.dart';
import '../models/staff_notification.dart';
import '../providers/order_events_provider.dart';
import '../providers/table_events_provider.dart';
import '../services/customer_sound_preference.dart';

/// Global "order progress" banner, floating above every screen in all three
/// app modes — the in-app half of the notification system (see
/// supabase/functions/order-event-notify for the push half). Mirrors
/// FloatingChatbotOverlay/QrChatbotOverlay's placement in main.dart's
/// overlay Stack and appMode-gating style.
///
/// [currentPath] is pushed down from RestaurantApp's ListenableBuilder on
/// the GoRouter instance, same reason QrChatbotOverlay needs it: this
/// widget sits outside GoRouter's own Navigator, so it has no Router
/// context of its own to read the current location from.
class OrderNotificationOverlay extends ConsumerStatefulWidget {
  final String currentPath;
  const OrderNotificationOverlay({super.key, required this.currentPath});

  @override
  ConsumerState<OrderNotificationOverlay> createState() =>
      _OrderNotificationOverlayState();
}

class _OrderNotificationOverlayState
    extends ConsumerState<OrderNotificationOverlay> {
  StaffNotification? _visible;
  String? _lastShownId;
  Timer? _dismissTimer;

  // _show() used to just overwrite _visible outright, so a second event
  // arriving while a banner was still up instantly replaced it — the
  // first notification's text was never actually readable, only its
  // chime and its entry in the notification bell's history survived.
  // Queue instead: every notification gets its own turn on screen.
  final List<StaffNotification> _pending = [];
  static const _maxPending = 12;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  bool get _onOrderTrackRoute {
    final segments =
        widget.currentPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return false;
    if (segments[0] == 'customer' && segments.length > 1 && segments[1] == 'track') {
      return true;
    }
    if (segments[0] == 'qr' && segments.length > 2 && segments[2] == 'track') {
      return true;
    }
    return false;
  }

  // Consent is scoped to one order, not the device — every fresh order
  // gets asked, even on a device that already said yes for a previous
  // one, and the flag naturally resets on any page reload (in-memory
  // only, see customer_sound_preference.dart). [_soundPromptHandled]
  // exists purely to stop the *same* build() rebuilding from re-showing
  // the dialog while it's already open/pending for this exact order.
  String? _soundPromptedForOrderId;

  Future<void> _maybeShowSoundPrompt(BuildContext context, String orderId) async {
    if (_soundPromptedForOrderId == orderId) return;
    _soundPromptedForOrderId = orderId;

    final current = CustomerSoundPreference.valueFor(orderId);
    if (current != null) return; // already decided for this exact order
    if (!context.mounted) return;

    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SoundPermissionDialog(),
    );
    CustomerSoundPreference.setEnabled(orderId, enable ?? false);
  }

  void _show(StaffNotification notification) {
    if (notification.id == _lastShownId) return;
    if (_visible?.id == notification.id) return;
    if (_pending.any((n) => n.id == notification.id)) return;

    // The chime fires immediately regardless of banner backlog — it's the
    // real-time alert, and OrderSoundService's own queue (see
    // order_sound_service.dart) already makes sure simultaneous chimes
    // play one after another instead of cutting each other off. Staff
    // always gets sound (no opt-out); customer/qr respects whatever the
    // diner answered for *this specific order's* permission dialog (see
    // _maybeShowSoundPrompt) — defaults to silent if there's no decision
    // on record for this order yet (e.g. the prompt hasn't resolved, or
    // this event fired before it even had a chance to run).
    final soundAllowed = appMode == 'staff' ||
        (notification.orderId != null &&
            CustomerSoundPreference.valueFor(notification.orderId!) == true);
    if (soundAllowed) OrderSoundService.play(notification.sound);

    if (_visible == null) {
      _display(notification);
    } else if (_pending.length < _maxPending) {
      _pending.add(notification);
    }
  }

  void _display(StaffNotification notification) {
    _lastShownId = notification.id;
    _dismissTimer?.cancel();
    setState(() => _visible = notification);
    // Drain a backlog faster than the normal 5s-per-banner pace so a
    // burst of events doesn't leave stale ones on screen for a minute.
    final duration = _pending.length > 3
        ? const Duration(seconds: 2, milliseconds: 500)
        : const Duration(seconds: 5);
    _dismissTimer = Timer(duration, _advance);
  }

  void _advance() {
    if (_pending.isEmpty) {
      if (mounted) setState(() => _visible = null);
      return;
    }
    final next = _pending.removeAt(0);
    if (mounted) _display(next);
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _advance();
  }

  /// Route segments this overlay must stay silent on entirely: payment
  /// flows, so it never interrupts an in-progress transaction. This is
  /// deliberately narrower than it used to be — the KDS screen was also
  /// blanket-suppressed here, which meant a multi-access role (e.g.
  /// superadmin, who can see Kitchen *and* Cashier *and* Table
  /// Management) got no banner/chime for anything — a payment completing,
  /// a table call — while just looking at the kitchen board. That's
  /// wrong: a role's access to a feature shouldn't depend on which
  /// screen they happen to be on right now. Only the literal new-order
  /// chime KDS already plays itself (see kds_screen.dart's
  /// _subscribeOrderEvents) is skipped here now, in [showIfRelevant]
  /// below — everything else this role has access to still gets through.
  bool get _suppressedForRoute {
    final segments =
        widget.currentPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return false;
    if (segments[0] == 'customer' &&
        segments.length > 1 &&
        segments[1] == 'payment') {
      return true;
    }
    if (segments[0] == 'qr' && segments.contains('pay')) return true;
    return false;
  }

  bool get _onKitchenRoute {
    final segments =
        widget.currentPath.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isNotEmpty && segments[0] == 'kitchen';
  }

  /// Order id for the QR app mode, read from the current route
  /// (`/qr/:tableId/track/:orderId`) — same extraction QrChatbotOverlay
  /// already performs for the same reason (no order-scoped state elsewhere
  /// for an anonymous QR session).
  String? get _qrOrderIdFromPath {
    final segments =
        widget.currentPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length < 4 || segments[0] != 'qr') return null;
    if (segments[2] != 'track') return null;
    return segments[3];
  }

  /// True the instant an order event signals the transaction is done —
  /// either the payment_status column landing on 'paid', or (the "Pay
  /// After Dining" flow) the order's own status reaching its terminal
  /// 'paid' step. Consent doesn't outlive the order it was granted for.
  bool _isPaymentComplete(OrderEvent e) =>
      e.newValue == 'paid' &&
      (e.eventType == OrderEventType.paymentStatusChanged ||
          e.eventType == OrderEventType.statusChanged);

  @override
  Widget build(BuildContext context) {
    if (_suppressedForRoute) return const SizedBox.shrink();

    final trackOrderId = appMode == 'qr'
        ? _qrOrderIdFromPath
        : appMode == 'customer'
            ? ref.watch(myActiveOrderIdProvider).value
            : null;
    if (trackOrderId != null && _onOrderTrackRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeShowSoundPrompt(context, trackOrderId);
      });
    }

    if (appMode == 'staff') {
      // null branchId (superadmin with no fixed home branch) means "all
      // branches" — see order_events_repository.dart's watchBranchEvents.
      // This used to skip subscribing entirely when null, so a superadmin
      // got no banner/chime anywhere in the staff app, not just on KDS.
      final branchId = ref.watch(currentBranchIdProvider);
      final role = ref.watch(currentStaffProvider)?.role;

      void showIfRelevant(StaffNotification notification) {
        // Same feature-access gate as the notification bell — a role with
        // no access to a notification's feature (e.g. host, who has
        // neither Kitchen nor Cashier access) doesn't get interrupted by
        // a banner/chime for it either.
        if (role != null && !notification.isRelevantToRole(role)) return;
        // Skip only the exact new-order chime KDS already plays itself
        // while staff is looking at that screen — everything else (a
        // payment completing, a table call, a bill request, even a
        // non-"new" Kitchen status change) still needs to reach a
        // multi-access role like superadmin/manager regardless of which
        // screen they're currently on.
        if (_onKitchenRoute &&
            notification.kind == StaffNotificationKind.order &&
            notification.isNewOrder) {
          return;
        }
        _show(notification);
      }

      ref.listen(orderEventsForBranchProvider(branchId), (prev, next) {
        next.whenData((event) =>
            showIfRelevant(StaffNotification.fromOrderEvent(event)));
      });
      ref.listen(tableEventsForBranchProvider(branchId), (prev, next) {
        next.whenData((event) =>
            showIfRelevant(StaffNotification.fromTableEvent(event)));
      });
    } else if (appMode == 'customer' || appMode == 'qr') {
      final orderId =
          appMode == 'customer' ? ref.watch(myActiveOrderIdProvider).value : _qrOrderIdFromPath;
      if (orderId != null) {
        ref.listen(orderEventsForOrderProvider(orderId), (prev, next) {
          next.whenData((event) {
            // Show (and, if consent was on, chime for) the payment-complete
            // event itself first — it's the last one consent should still
            // cover — then revoke so anything from here on stays silent.
            _show(StaffNotification.fromOrderEvent(event));
            if (_isPaymentComplete(event)) {
              CustomerSoundPreference.revokeForOrder(orderId);
            }
          });
        });
      }
    }

    final notification = _visible;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -1),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: notification == null
              ? const SizedBox.shrink(key: ValueKey('empty'))
              : _Banner(
                  key: ValueKey(notification.id),
                  notification: notification,
                  onDismiss: _dismiss,
                  onTap: () {
                    _dismiss();
                    if (appMode == 'staff') {
                      context.go(notification.kind == StaffNotificationKind.table
                          ? AppRoutes.tables
                          : AppRoutes.order);
                    } else if (appMode == 'customer') {
                      context.go('/customer/track/${notification.orderNumber}');
                    } else if (appMode == 'qr') {
                      final segments = widget.currentPath
                          .split('/')
                          .where((s) => s.isNotEmpty)
                          .toList();
                      if (segments.length >= 2 && segments[0] == 'qr') {
                        context.go('/qr/${segments[1]}/track/${notification.orderId}');
                      }
                    }
                  },
                ),
        ),
      ),
    );
  }
}

/// Modal "ask once" permission prompt for order-progress chimes, shown the
/// first time a diner lands on their order tracker (see
/// _OrderNotificationOverlayState._maybeShowSoundPrompt) — same UX pattern
/// as a weather app asking to enable location before it can push forecast
/// alerts: explain the value up front, ask for one deliberate tap, then
/// never ask again (CustomerSoundPreference persists the answer).
class _SoundPermissionDialog extends StatelessWidget {
  const _SoundPermissionDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.volume_up_rounded,
                  color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aktifkan Suara Notifikasi?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kami akan memberi tahu progres pesanan Anda lewat suara — '
              'mulai dimasak, siap disajikan, hingga pembayaran — supaya '
              'Anda tidak perlu terus memantau layar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Aktifkan Suara',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Nanti Saja',
                style: TextStyle(
                    fontFamily: 'Poppins', color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final StaffNotification notification;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _Banner({
    super.key,
    required this.notification,
    required this.onDismiss,
    required this.onTap,
  });

  IconData get _icon {
    if (notification.kind == StaffNotificationKind.table) {
      return Icons.room_service_rounded;
    }
    switch (notification.orderEventType) {
      case OrderEventType.statusChanged:
        return notification.isNewOrder
            ? Icons.receipt_long_rounded
            : Icons.autorenew_rounded;
      case OrderEventType.paymentStatusChanged:
        return Icons.payments_rounded;
      case OrderEventType.billRequested:
        return Icons.request_page_rounded;
      case OrderEventType.cancelled:
        return Icons.cancel_rounded;
      case null:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        color: AppColors.primary,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(_icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notification.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onDismiss,
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
