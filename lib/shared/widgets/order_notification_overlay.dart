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
import '../providers/order_events_provider.dart';

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
  OrderEvent? _visible;
  String? _lastShownEventId;
  Timer? _dismissTimer;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _show(OrderEvent event) {
    if (event.id == _lastShownEventId) return;
    _lastShownEventId = event.id;
    _dismissTimer?.cancel();
    setState(() => _visible = event);
    OrderSoundService.playNewOrder();
    _dismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _visible = null);
    });
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    if (mounted) setState(() => _visible = null);
  }

  /// Route segments this overlay must stay silent on: payment flows (never
  /// interrupt an in-progress transaction) and the KDS screen (which shows
  /// its own dedicated new-order banner — see kds_screen.dart's
  /// _buildNewOrderBanner — so the two mechanisms don't compete).
  bool get _suppressedForRoute {
    final segments =
        widget.currentPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return false;
    if (segments[0] == 'kitchen') return true; // staff KDS
    if (segments[0] == 'customer' &&
        segments.length > 1 &&
        segments[1] == 'payment') {
      return true;
    }
    if (segments[0] == 'qr' && segments.contains('pay')) return true;
    return false;
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

  @override
  Widget build(BuildContext context) {
    if (_suppressedForRoute) return const SizedBox.shrink();

    if (appMode == 'staff') {
      final branchId = ref.watch(currentBranchIdProvider);
      if (branchId != null) {
        ref.listen(orderEventsForBranchProvider(branchId), (prev, next) {
          next.whenData(_show);
        });
      }
    } else if (appMode == 'customer') {
      final orderId = ref.watch(myActiveOrderIdProvider).value;
      if (orderId != null) {
        ref.listen(orderEventsForOrderProvider(orderId), (prev, next) {
          next.whenData(_show);
        });
      }
    } else if (appMode == 'qr') {
      final orderId = _qrOrderIdFromPath;
      if (orderId != null) {
        ref.listen(orderEventsForOrderProvider(orderId), (prev, next) {
          next.whenData(_show);
        });
      }
    }

    final event = _visible;
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
          child: event == null
              ? const SizedBox.shrink(key: ValueKey('empty'))
              : _Banner(
                  key: ValueKey(event.id),
                  event: event,
                  onDismiss: _dismiss,
                  onTap: () {
                    _dismiss();
                    if (appMode == 'staff') {
                      context.go(AppRoutes.order);
                    } else if (appMode == 'customer') {
                      context.go('/customer/track/${event.orderNumber}');
                    } else if (appMode == 'qr') {
                      final segments = widget.currentPath
                          .split('/')
                          .where((s) => s.isNotEmpty)
                          .toList();
                      if (segments.length >= 2 && segments[0] == 'qr') {
                        context.go('/qr/${segments[1]}/track/${event.orderId}');
                      }
                    }
                  },
                ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final OrderEvent event;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _Banner({
    super.key,
    required this.event,
    required this.onDismiss,
    required this.onTap,
  });

  IconData get _icon {
    switch (event.eventType) {
      case OrderEventType.statusChanged:
        return event.oldValue == null
            ? Icons.receipt_long_rounded
            : Icons.autorenew_rounded;
      case OrderEventType.paymentStatusChanged:
        return Icons.payments_rounded;
      case OrderEventType.billRequested:
        return Icons.request_page_rounded;
      case OrderEventType.cancelled:
        return Icons.cancel_rounded;
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
                    event.message,
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
