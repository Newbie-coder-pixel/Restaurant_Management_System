// lib/core/theme/app_theme.dart
//
// Color/type tokens follow DESIGN.md ("Pusaka" design system) — keep the two
// in sync when either changes.
import 'package:flutter/material.dart';

class AppColors {
  static const primary        = Color(0xFFC08A17); // gold/mustard
  static const primaryLight   = Color(0xFFD9A53F);
  static const accent         = Color(0xFFA6491F); // terracotta/rust
  static const accentOrange   = Color(0xFFD97706);

  static const available      = Color(0xFF4CAF50);
  static const occupied       = Color(0xFFA6491F);
  static const reserved       = Color(0xFFD97706);
  static const cleaning       = Color(0xFF2196F3);

  static const orderNew       = Color(0xFF9C27B0);
  static const orderPreparing = Color(0xFFD97706);
  static const orderReady     = Color(0xFF4CAF50);
  static const orderServed    = Color(0xFF607D8B);

  // Status tokens (bookings / order tracking badges)
  static const statusConfirmed  = primary;
  static const statusWaitlist   = Color(0xFFD97706);
  static const statusCompleted  = Color(0xFF9C9690);
  static const statusClosed     = Color(0xFFE8A0A0);
  static const badgeDark        = Color(0xFF22284A);
  static const iconAccentBlue   = Color(0xFF4C5FD5);

  static const background     = Color(0xFFFAF6ED);
  static const surface        = Color(0xFFFDFBF5);
  static const surfaceVariant = Color(0xFFF1EDE2);
  static const footerBackground = Color(0xFFE2DED4);
  static const border         = Color(0xFFE4DFD2);
  static const textPrimary    = Color(0xFF221F1B);
  static const textSecondary  = Color(0xFF6E6A63);
  static const textHint       = Color(0xFF9C9690);

  static const darkBackground    = Color(0xFF0F0F1A);
  static const darkSurface       = Color(0xFF1A1A2E);
  static const darkSurfaceVariant = Color(0xFF16213E);
}

class AppSpacing {
  static const xs = 8.0;
  static const sm = 16.0;
  static const md = 24.0;
  static const lg = 32.0;
  static const xl = 48.0;

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;
  static const radiusPill = 999.0;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Poppins',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.background,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  // Dark theme for KDS
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Poppins',
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.dark,
        primary: AppColors.accent,
        surface: AppColors.darkSurface,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2A2A4A), width: 1),
        ),
      ),
    );
  }
}

class AppTextStyles {
  static const heading1 = TextStyle(
    fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const heading2 = TextStyle(
    fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const heading3 = TextStyle(
    fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontFamily: 'Poppins', fontSize: 14, color: AppColors.textPrimary,
  );
  static const bodySecondary = TextStyle(
    fontFamily: 'Poppins', fontSize: 14, color: AppColors.textSecondary,
  );
  static const caption = TextStyle(
    fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary,
  );
  static const label = TextStyle(
    fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );
}