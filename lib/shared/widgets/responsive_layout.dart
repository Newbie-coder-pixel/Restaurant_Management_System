import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveLayout({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isDesktop = screenWidth > 1200;
        final isTablet = screenWidth > 768;

        final effectiveMaxWidth =
            maxWidth ??
            (isDesktop
                ? 1200.0
                : isTablet
                ? 800.0
                : double.infinity);
        final effectivePadding =
            padding ??
            EdgeInsets.symmetric(
              horizontal: isDesktop
                  ? 32.0
                  : isTablet
                  ? 24.0
                  : 16.0,
            );

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
            child: Padding(padding: effectivePadding, child: child),
          ),
        );
      },
    );
  }
}

// Responsive gap helper (no deps)
class ResponsiveGap extends StatelessWidget {
  final double heightFactor;
  final double widthFactor;
  final bool isHeight;

  // FIX: Tambah {super.key} → fixes use_key_in_widget_constructors
  // FIX: Gunakan this.heightFactor / this.widthFactor → fixes prefer_initializing_formals
  const ResponsiveGap.height(this.heightFactor, {super.key})
    : widthFactor = 0,
      isHeight = true;

  const ResponsiveGap.width(this.widthFactor, {super.key})
    : heightFactor = 0,
      isHeight = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final size = isHeight
        ? screenSize.height * heightFactor
        : screenSize.width * widthFactor;
    return SizedBox(
      height: isHeight ? size : null,
      width: isHeight ? null : size,
    );
  }
}