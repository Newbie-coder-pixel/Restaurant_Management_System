// lib/shared/widgets/theme_mode_toggle.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/theme_mode_provider.dart';
import '../../core/theme/app_theme.dart';

/// Global Light/Dark/System toggle, floating alongside the chatbot and
/// notification overlays in every app mode (see main.dart) — the "way to
/// customize the app's look and feel" a generic/reusable RestaurantOS
/// deployment needs, independent of any one restaurant's brand colors.
///
/// A single tap cycles System → Light → Dark → System (ThemeModeNotifier.
/// cycle()) rather than opening a menu/dialog: this widget lives in the
/// same plain Overlay, outside GoRouter's own Navigator, that broke
/// showDialog() for the sound-permission prompt (see order_notification_
/// overlay.dart's _maybeShowSoundPrompt fix) — cycling on tap sidesteps
/// that whole class of bug by never needing a Navigator at all.
class ThemeModeToggle extends ConsumerWidget {
  const ThemeModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Positioned(
      left: 12,
      bottom: 12,
      child: SafeArea(
        child: Tooltip(
          message: 'Theme: ${_label(mode)} (tap to change)',
          child: Material(
            color: AppColors.surface,
            elevation: 4,
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => ref.read(themeModeProvider.notifier).cycle(),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(_icon(mode), size: 20, color: AppColors.primary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _icon(ThemeMode mode) => switch (mode) {
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
        ThemeMode.system => Icons.brightness_auto_rounded,
      };

  String _label(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Automatic',
      };
}
