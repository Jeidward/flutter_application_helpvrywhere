import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// HelpEverywhere brand tokens — colors, typography, spacing.
///
/// Scoped: applied only to the nearby-request flow via a Theme wrapper on
/// each screen. The rest of the app keeps its existing global theme so we
/// don't accidentally restyle auth / profile / overlay screens.
class AppColors {
  static const primaryBlue = Color(0xFF3B82F6);
  static const primaryGreen = Color(0xFF10B981);
  static const darkNavy = Color(0xFF0A0F1A);
  static const lightBlue = Color(0xFFEFF6FF);
  static const lightGreen = Color(0xFFECFDF5);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const bg = Color(0xFFF5F6F8);
  static const surface = Colors.white;

  // Category tints (foreground / background pairs)
  static const householdFg = primaryBlue;
  static const householdBg = lightBlue;
  static const groceriesFg = primaryGreen;
  static const groceriesBg = lightGreen;
  static const transportFg = Color(0xFFB45309);
  static const transportBg = Color(0xFFFEF3F2);
  static const techFg = Color(0xFF6D28D9);
  static const techBg = Color(0xFFF3F0FF);

  // Safety banner
  static const safetyText = Color(0xFF065F46);
  static const safetyTitle = Color(0xFF064E3B);
}

class AppRadius {
  static const card = 16.0;
  static const tile = 14.0;
  static const pill = 999.0;
  static const sheet = 24.0;
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 18.0;
  static const xxl = 24.0;
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        primary: AppColors.primaryBlue,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      splashFactory: InkRipple.splashFactory,
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.darkNavy,
      displayColor: AppColors.darkNavy,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        // Section title (e.g. "Change a high ceiling lightbulb")
        titleLarge: textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.44,
          height: 1.18,
        ),
        // App-bar title
        titleMedium: textTheme.titleMedium?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        // Card title
        titleSmall: textTheme.titleSmall?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.14,
          height: 1.3,
        ),
        // Body
        bodyMedium: textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.55,
          color: AppColors.muted,
        ),
        // Meta (12px)
        bodySmall: textTheme.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.4,
          color: AppColors.muted,
        ),
        // Labels
        labelLarge: textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: textTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.055,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.darkNavy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        space: 1,
        thickness: 1,
      ),
    );
  }
}
