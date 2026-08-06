import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/chatbot/presentation/chatbot_screen.dart';

/// Floating AI Chatbot launcher shown on top of every staff screen, replacing
/// the old sidebar/drawer entry. Only visible to logged-in staff whose role
/// has the 'AI Chatbot' access feature (superadmin, manager).
class FloatingChatbotOverlay extends ConsumerStatefulWidget {
  const FloatingChatbotOverlay({super.key});

  @override
  ConsumerState<FloatingChatbotOverlay> createState() =>
      _FloatingChatbotOverlayState();
}

class _FloatingChatbotOverlayState
    extends ConsumerState<FloatingChatbotOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (appMode != 'staff') return const SizedBox.shrink();

    final staff = ref.watch(currentStaffProvider);
    if (staff == null || !staff.role.accessFeatures.contains('AI Chatbot')) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.of(context).size;
    final panelWidth = size.width < 420 ? size.width - 32 : 380.0;
    final panelHeight = (size.height * 0.75).clamp(420.0, 640.0);

    return SafeArea(
      child: Stack(
        children: [
          if (_open)
            Positioned(
              right: 16,
              bottom: 156,
              child: SizedBox(
                width: panelWidth,
                height: panelHeight,
                child: ChatbotScreen(
                  embedded: true,
                  onClose: () => setState(() => _open = false),
                ),
              ),
            ),
          // Offset well above the standard bottom-right Scaffold FAB slot
          // (many staff screens — Menu, Table Management — already have their
          // own "Add" FAB there) so the two never overlap.
          Positioned(
            right: 16,
            bottom: 88,
            child: FloatingActionButton(
              heroTag: 'ai_chatbot_fab',
              backgroundColor: AppColors.primary,
              onPressed: () => setState(() => _open = !_open),
              child: Icon(
                _open ? Icons.close_rounded : Icons.smart_toy_rounded,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
