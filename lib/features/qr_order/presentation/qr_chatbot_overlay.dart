// lib/features/qr_order/presentation/qr_chatbot_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../providers/qr_cart_provider.dart';
import 'qr_chatbot_screen.dart';

/// Extra vertical space to clear the menu screen's own "Cart Rp XX" pill
/// (`_CartFab` in qr_menu_screen.dart), which occupies the same bottom-right
/// corner as this overlay's FAB whenever the cart has items.
const double _cartPillClearance = 64.0;

/// Floating "Menu Assistant" launcher for the QR app. Visible only while
/// browsing the menu (`/qr/:tableId`) or tracking an order
/// (`/qr/:tableId/track/:orderId`) — hidden on cart/checkout and payment
/// screens per product decision to keep the AI panel out of the way during
/// the actual transaction, then bring it back once the order is placed.
///
/// [currentPath] is pushed down from RestaurantApp's ListenableBuilder on
/// the GoRouter instance, since this overlay sits outside GoRouter's own
/// Navigator (see the comment in main.dart) and has no Router context of
/// its own to read the location from.
class QrChatbotOverlay extends ConsumerStatefulWidget {
  final String currentPath;
  const QrChatbotOverlay({super.key, required this.currentPath});

  @override
  ConsumerState<QrChatbotOverlay> createState() => _QrChatbotOverlayState();
}

class _QrChatbotOverlayState extends ConsumerState<QrChatbotOverlay> {
  bool _open = false;

  ({bool visible, String? tableId, bool allowAddToCart, bool onMenuScreen})
      get _routeInfo {
    final segments =
        widget.currentPath.split('/').where((s) => s.isNotEmpty).toList();
    // ['qr', tableId, ...rest]
    if (segments.length < 2 || segments[0] != 'qr') {
      return (
        visible: false,
        tableId: null,
        allowAddToCart: false,
        onMenuScreen: false
      );
    }
    final tableId = segments[1];
    final rest = segments.sublist(2);
    if (rest.isEmpty) {
      return (
        visible: true,
        tableId: tableId,
        allowAddToCart: true,
        onMenuScreen: true
      ); // menu
    }
    if (rest.first == 'track') {
      return (
        visible: true,
        tableId: tableId,
        allowAddToCart: false,
        onMenuScreen: false
      ); // tracker
    }
    return (
      visible: false,
      tableId: tableId,
      allowAddToCart: false,
      onMenuScreen: false
    ); // cart, pay
  }

  @override
  Widget build(BuildContext context) {
    if (appMode != 'qr') return const SizedBox.shrink();

    final info = _routeInfo;
    // Second, route-independent guard — see qrChatbotSuppressedProvider's
    // doc comment. The FAB must never be able to sit on top of the cart's
    // "Order Now" button, even if the route-string check above ever
    // disagrees with what's actually on screen.
    final suppressed = ref.watch(qrChatbotSuppressedProvider);
    final visible = info.visible && !suppressed;

    // The menu screen shows its own "Cart Rp XX" pill (Scaffold FAB) in the
    // same bottom-right corner once the cart has items — lift this FAB (and
    // its chat panel) clear of it instead of letting them overlap.
    final cartHasItems = ref.watch(
      activeQrCartProvider.select((cart) => !cart.isEmpty),
    );
    final liftForCartPill =
        (info.onMenuScreen && cartHasItems) ? _cartPillClearance : 0.0;
    final fabBottom = 24 + liftForCartPill;
    final panelBottom = 96 + liftForCartPill;

    final size = MediaQuery.of(context).size;
    final panelWidth = size.width < 420 ? size.width - 32 : 380.0;
    final panelHeight = (size.height * 0.7).clamp(400.0, 620.0);

    return SafeArea(
      child: Stack(
        children: [
          // Offstage (not removed) so the conversation survives navigating
          // away and back — e.g. menu -> cart -> tracker keeps chat history.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            right: 16,
            bottom: panelBottom,
            child: Offstage(
              offstage: !(visible && _open && info.tableId != null),
              child: SizedBox(
                width: panelWidth,
                height: panelHeight,
                child: info.tableId == null
                    ? const SizedBox.shrink()
                    : QrChatbotScreen(
                        key: ValueKey(info.tableId),
                        tableId: info.tableId!,
                        allowAddToCart: info.allowAddToCart,
                        onClose: () => setState(() => _open = false),
                      ),
              ),
            ),
          ),
          if (visible)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              right: 16,
              bottom: fabBottom,
              child: FloatingActionButton(
                heroTag: 'qr_chatbot_fab',
                backgroundColor: Theme.of(context).colorScheme.primary,
                onPressed: () => setState(() => _open = !_open),
                child: Icon(
                  _open ? Icons.close_rounded : Icons.smart_toy_rounded,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
