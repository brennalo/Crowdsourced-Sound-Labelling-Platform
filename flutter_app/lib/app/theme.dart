import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Forest Sound Platform color palette.
/// Not generated via ColorScheme.fromSeed — neutrals are hand-picked so the
/// app reads as warm/organic (cream paper, soft green) rather than the
/// default Material grey.
class AppColors {
  AppColors._();

  // Core palette
  static const canopy = Color(0xFF2D6A4F); // primary — deep forest green
  static const canopyDark = Color(0xFF1B4332);
  static const moss = Color(0xFF95D5B2); // secondary — light sage
  static const mossLight = Color(0xFFD8F3DC);
  static const amber = Color(0xFFE9C46A); // accent — growth / highlight
  static const bark = Color(0xFFD4A373); // accent — warm brown
  static const warnRed =
      Color(0xFFBC4749); // desaturated red, not pure Material error

  // Light theme neutrals
  static const creamBackground = Color(0xFFFAF7F0);
  static const creamSurface = Color(0xFFF1EDE4);
  static const creamSurfaceHigh = Color(0xFFE9E3D5);
  static const inkText = Color(0xFF1F2A22);
  static const inkTextMuted = Color(0xFF5B6B5F);

  // Dark theme neutrals — deep night-forest, not pure black
  static const nightBackground = Color(0xFF16231C);
  static const nightSurface = Color(0xFF1F3226);
  static const nightSurfaceHigh = Color(0xFF294432);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: AppColors.moss,
            onPrimary: AppColors.nightBackground,
            primaryContainer: AppColors.canopyDark,
            onPrimaryContainer: AppColors.mossLight,
            secondary: AppColors.amber,
            onSecondary: AppColors.nightBackground,
            secondaryContainer: Color(0xFF4A3B1F),
            onSecondaryContainer: AppColors.amber,
            error: AppColors.warnRed,
            onError: Colors.white,
            errorContainer: Color(0xFF4A2325),
            onErrorContainer: Color(0xFFFFDAD9),
            surface: AppColors.nightSurface,
            onSurface: Color(0xFFE3E9E4),
            surfaceContainerHigh: AppColors.nightSurfaceHigh,
            outline: Color(0xFF8A9A8E),
          )
        : const ColorScheme.light(
            primary: AppColors.canopy,
            onPrimary: Colors.white,
            primaryContainer: AppColors.mossLight,
            onPrimaryContainer: AppColors.canopyDark,
            secondary: AppColors.bark,
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFFFAE8CC),
            onSecondaryContainer: Color(0xFF6B4A1E),
            error: AppColors.warnRed,
            onError: Colors.white,
            errorContainer: Color(0xFFF6DCDA),
            onErrorContainer: Color(0xFF5C1D1E),
            surface: AppColors.creamSurface,
            onSurface: AppColors.inkText,
            surfaceContainerHigh: AppColors.creamSurfaceHigh,
            outline: AppColors.inkTextMuted,
          );

    final base = ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.nightBackground : AppColors.creamBackground,
      useMaterial3: true,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: GoogleFonts.interTextTheme().copyWith(
        // Display/headline styles get the rounder, friendlier display font —
        // used for screen titles, stage names, big stat numbers.
        displayLarge: GoogleFonts.baloo2(fontWeight: FontWeight.w600),
        displayMedium: GoogleFonts.baloo2(fontWeight: FontWeight.w600),
        displaySmall: GoogleFonts.baloo2(fontWeight: FontWeight.w600),
        headlineLarge: GoogleFonts.baloo2(fontWeight: FontWeight.w600),
        headlineMedium: GoogleFonts.baloo2(fontWeight: FontWeight.w600),
        headlineSmall: GoogleFonts.baloo2(fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.baloo2(fontWeight: FontWeight.w600),
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? AppColors.nightBackground : AppColors.creamBackground,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.baloo2(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.nightSurfaceHigh : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle:
              GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide(color: colorScheme.outline.withOpacity(0.4)),
          textStyle:
              GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        side: BorderSide.none,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.nightSurface : Colors.white,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary.withOpacity(0.4)
              : null,
        ),
      ),
    );
  }
}

/// Semantic label colors — used anywhere a "chainsaw" vs "environment" (or
/// future labels) status needs a color. Keeps chainsaw/warning off pure
/// Material red and environment/success off pure Material green so both
/// sit naturally inside the forest palette instead of clashing with it.
class LabelColors {
  LabelColors._();

  static Color forLabel(String? label, ColorScheme scheme) {
    switch (label) {
      case 'chainsaw':
        return AppColors.warnRed;
      case 'environment':
        return AppColors.canopy;
      default:
        return scheme.outline;
    }
  }

  static Color containerForLabel(String? label, ColorScheme scheme) {
    switch (label) {
      case 'chainsaw':
        return scheme.errorContainer;
      case 'environment':
        return scheme.primaryContainer;
      default:
        return scheme.surfaceContainerHigh;
    }
  }
}
