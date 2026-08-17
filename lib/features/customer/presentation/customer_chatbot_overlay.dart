// lib/features/customer/presentation/customer_chatbot_overlay.dart
import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_chatbot_screen.dart';

/// Extra vertical clearance for the payment screen's full-width "Pay" bar
/// (`customer_pay_now_screen.dart`), which otherwise sits directly under
/// this overlay's default bottom-right position.
const double _payBarClearance = 70.0;

/// Floating AI chat launcher for the customer app. Mounted once in
/// main.dart (see QrChatbotOverlay's doc comment for why: it needs an
/// Overlay ancestor of its own for Material/InkWell effects, which it gets
/// by living alongside `child` rather than inside it) instead of being
/// rebuilt per-screen — so it now survives navigating to any `/customer/*`
/// route (menu, checkout, payment, tracker, etc.), not just
/// CustomerLandingScreen's own tabs, where it used to live exclusively.
///
/// [currentPath] is pushed down from RestaurantApp's ListenableBuilder on
/// the GoRouter instance, since this overlay sits outside GoRouter's own
/// Navigator and has no Router context of its own to read the location
/// from.
class CustomerChatbotOverlay extends StatefulWidget {
  final String currentPath;
  const CustomerChatbotOverlay({super.key, required this.currentPath});

  @override
  State<CustomerChatbotOverlay> createState() =>
      _CustomerChatbotOverlayState();
}

class _CustomerChatbotOverlayState extends State<CustomerChatbotOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (appMode != 'customer') return const SizedBox.shrink();
    if (!widget.currentPath.startsWith('/customer')) {
      return const SizedBox.shrink();
    }

    final liftForPayBar =
        widget.currentPath.startsWith('/customer/payment') ? _payBarClearance : 0.0;
    final fabBottom = 20 + liftForPayBar;
    final panelBottom = 88 + liftForPayBar;

    final size = MediaQuery.of(context).size;
    final panelWidth = size.width < 420 ? size.width - 32 : 380.0;
    final panelHeight = (size.height * 0.72).clamp(420.0, 640.0);

    return SafeArea(
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            right: 16,
            bottom: panelBottom,
            child: Offstage(
              // Not removed so the conversation survives closing/reopening
              // the panel and navigating between customer screens.
              offstage: !_open,
              child: SizedBox(
                width: panelWidth,
                height: panelHeight,
                child: CustomerChatbotScreen(
                  onClose: () => setState(() => _open = false),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            right: 16,
            bottom: fabBottom,
            child: FloatingActionButton(
              heroTag: 'customer_chatbot_fab',
              backgroundColor: AppColors.primary,
              onPressed: () => setState(() => _open = !_open),
              child: Icon(_open ? Icons.close_rounded : Icons.chat_rounded,
                  color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
