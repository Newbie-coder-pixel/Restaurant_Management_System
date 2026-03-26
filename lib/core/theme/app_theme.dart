// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppColors {
  static const primary        = Color(0xFF1A1A2E);
  static const primaryLight   = Color(0xFF16213E);
  static const accent         = Color(0xFFE94560);
  static const accentOrange   = Color(0xFFFF6B35);

  static const available      = Color(0xFF4CAF50);
  static const occupied       = Color(0xFFE94560);
  static const reserved       = Color(0xFFFF9800);
  static const cleaning       = Color(0xFF2196F3);

  static const orderNew       = Color(0xFF9C27B0);
  static const orderPreparing = Color(0xFFFF9800);
  static const orderReady     = Color(0xFF4CAF50);
  static const orderServed    = Color(0xFF607D8B);

  static const background     = Color(0xFFF8F9FA);
  static const surface        = Colors.white;
  static const surfaceVariant = Color(0xFFF1F3F4);
  static const border         = Color(0xFFE8EAED);
  static const textPrimary    = Color(0xFF1A1A2E);
  static const textSecondary  = Color(0xFF6B7280);
  static const textHint       = Color(0xFF9CA3AF);

  static const darkBackground    = Color(0xFF0F0F1A);
  static const darkSurface       = Color(0xFF1A1A2E);
  static const darkSurfaceVariant = Color(0xFF16213E);
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
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  // Dark theme untuk KDS
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