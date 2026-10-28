import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized design system for Billk Motolink.
///
/// UI/UX ONLY: this file contains no business logic and touches no
/// Firestore paths. It only changes how existing widgets *look* by
/// supplying richer ThemeData so every screen that already reads
/// `Theme.of(context)` (AppBar, Card, ElevatedButton, TextField, etc.)
/// automatically picks up a consistent, more professional appearance.
class AppTheme {
  AppTheme._();

  // Brand seed — keeps the existing teal identity but derives a full,
  // accessible Material 3 palette from it instead of scattered raw colors.
  static const Color _seed = Color(0xFF0F766E); // deep teal
  static const Color _successColor = Color(0xFF2E7D32);
  static const Color _warningColor = Color(0xFFB26A00);
  static const Color _dangerColor = Color(0xFFC62828);

  static Color get success => _successColor;
  static Color get warning => _warningColor;
  static Color get danger => _dangerColor;

  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Hand-tuned palette on top of the seeded scheme.
  /// Light: cool off-white canvas with pure-white cards separated by a
  /// hairline border (no heavy shadows). Dark: tinted near-black with
  /// stepped surfaces so cards read by tone, not by glow.
  static ColorScheme _scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    if (brightness == Brightness.dark) {
      return base.copyWith(
        primary: const Color(0xFF4FD1C0),
        onPrimary: const Color(0xFF00201C),
        primaryContainer: const Color(0xFF0F4F48),
        onPrimaryContainer: const Color(0xFFB8F2E9),
        surface: const Color(0xFF111917),
        onSurface: const Color(0xFFE6EEEC),
        onSurfaceVariant: const Color(0xFF9DB0AB),
        surfaceContainerLowest: const Color(0xFF0B1110),
        surfaceContainerLow: const Color(0xFF141D1B),
        surfaceContainer: const Color(0xFF182321),
        surfaceContainerHigh: const Color(0xFF1D2927),
        surfaceContainerHighest: const Color(0xFF243230),
        outline: const Color(0xFF5E706B),
        outlineVariant: const Color(0xFF26332F),
        surfaceTint: Colors.transparent,
      );
    }
    return base.copyWith(
      primary: const Color(0xFF0F766E),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD5F0EB),
      onPrimaryContainer: const Color(0xFF053B35),
      surface: Colors.white,
      onSurface: const Color(0xFF0F1A17),
      onSurfaceVariant: const Color(0xFF55655F),
      surfaceContainerLowest: const Color(0xFFF3F6F5),
      surfaceContainerLow: Colors.white,
      surfaceContainer: const Color(0xFFF7FAF9),
      surfaceContainerHigh: const Color(0xFFEEF3F1),
      surfaceContainerHighest: const Color(0xFFE8EEEC),
      outline: const Color(0xFF8A9A95),
      outlineVariant: const Color(0xFFDFE7E4),
      surfaceTint: Colors.transparent,
    );
  }

  /// Status-bar icon style for the given brightness (transparent bar).
  static SystemUiOverlayStyle overlayFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = _scheme(brightness);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: 'MyFont',
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: base.scaffoldBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayFor(brightness),
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'MyFont',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'MyFont',
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'MyFont',
          fontSize: 14.5,
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        elevation: 4,
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 24,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),

      expansionTileTheme: ExpansionTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        iconColor: colorScheme.primary,
        collapsedIconColor: colorScheme.onSurfaceVariant,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 3,
      ),

      badgeTheme: BadgeThemeData(
        backgroundColor: colorScheme.error,
        textColor: colorScheme.onError,
      ),
    );
  }
}

/// Small shared status-color helper so pages that show
/// present/absent/success/warning/error states use one
/// consistent palette instead of ad-hoc Colors.green/red.
class AppStatusColors {
  AppStatusColors._();

  static Color present(ColorScheme scheme) => AppTheme.success;
  static Color absent(ColorScheme scheme) => AppTheme.danger;
  static Color pending(ColorScheme scheme) => AppTheme.warning;
}
