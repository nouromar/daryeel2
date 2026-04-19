import 'package:flutter/material.dart';

ThemeData resolveCustomerTheme(
  Map<String, Object?> document, {
  String? overrideMode,
}) {
  final themeId = document['themeId'] as String? ?? 'customer-default';
  final mode = overrideMode ?? document['themeMode'] as String? ?? 'light';
  final tokens = _resolveTokens(themeId: themeId, mode: mode);
  final primary = _parseHex(tokens['color.action.brand']!);
  final surface = _parseHex(tokens['color.surface.primary']!);
  final surfaceSubtle = _parseHex(tokens['color.surface.subtle']!);
  final textPrimary = _parseHex(tokens['color.text.primary']!);
  final textSecondary = _parseHex(tokens['color.text.secondary']!);
  final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;
  final onPrimary = _onColorFor(primary);
  final textTheme = _buildTextTheme(
    textPrimary: textPrimary,
    textSecondary: textSecondary,
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      error: const Color(0xFFB91C1C),
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      tertiary: surfaceSubtle,
      onTertiary: textSecondary,
    ),
    scaffoldBackgroundColor: surfaceSubtle,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textTheme: textTheme,
  );
}

ThemeMode resolveThemeMode(Map<String, Object?> document) {
  final mode = document['themeMode'] as String? ?? 'light';
  return mode == 'dark' ? ThemeMode.dark : ThemeMode.light;
}

Color _parseHex(String value) {
  final sanitized = value.replaceFirst('#', '');
  return Color(int.parse('FF$sanitized', radix: 16));
}

Color _onColorFor(Color background) {
  // Use luminance to ensure button text stays readable for light/dark primaries.
  return background.computeLuminance() > 0.55 ? Colors.black : Colors.white;
}

Map<String, String> _resolveTokens({
  required String themeId,
  required String mode,
}) {
  final isDark = mode == 'dark';
  final theme = _themeTokens[themeId] ?? _themeTokens['customer-default']!;
  return isDark ? theme.dark : theme.light;
}

TextTheme _buildTextTheme({
  required Color textPrimary,
  required Color textSecondary,
}) {
  // Centralized typography scale used across schema-driven widgets.
  // Muted/caption/labels should generally use `textSecondary`.
  return TextTheme(
    displayLarge: TextStyle(
      color: textPrimary,
      fontSize: 40,
      fontWeight: FontWeight.w800,
      height: 1.1,
    ),
    displayMedium: TextStyle(
      color: textPrimary,
      fontSize: 34,
      fontWeight: FontWeight.w800,
      height: 1.12,
    ),
    displaySmall: TextStyle(
      color: textPrimary,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.15,
    ),

    headlineLarge: TextStyle(
      color: textPrimary,
      fontSize: 32,
      fontWeight: FontWeight.w800,
      height: 1.15,
    ),
    headlineMedium: TextStyle(
      color: textPrimary,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    // Previously defined in this app theme.
    headlineSmall: TextStyle(
      color: textPrimary,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),

    // Previously defined in this app theme.
    titleLarge: TextStyle(
      color: textPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
    // Previously defined in this app theme.
    titleMedium: TextStyle(
      color: textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
    titleSmall: TextStyle(
      color: textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),

    bodyLarge: TextStyle(
      color: textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    // Previously defined in this app theme.
    bodyMedium: TextStyle(
      color: textSecondary,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    bodySmall: TextStyle(
      color: textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.35,
    ),

    labelLarge: TextStyle(
      color: textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    labelMedium: TextStyle(
      color: textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    labelSmall: TextStyle(
      color: textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
  );
}

class _ThemeTokenPair {
  const _ThemeTokenPair({required this.light, required this.dark});

  final Map<String, String> light;
  final Map<String, String> dark;
}

const _themeTokens = <String, _ThemeTokenPair>{
  'customer-default': _ThemeTokenPair(
    light: <String, String>{
      'color.surface.primary': '#FFFFFF',
      'color.surface.subtle': '#F8FAFC',
      'color.text.primary': '#0F172A',
      'color.text.secondary': '#475569',
      'color.action.brand': '#0F766E',
    },
    dark: <String, String>{
      'color.surface.primary': '#0F172A',
      'color.surface.subtle': '#111827',
      'color.text.primary': '#F8FAFC',
      'color.text.secondary': '#CBD5E1',
      'color.action.brand': '#14B8A6',
    },
  ),

  // High-contrast, black/white, card-first look.
  'custome-black-white-clear': _ThemeTokenPair(
    light: <String, String>{
      'color.surface.primary': '#FFFFFF',
      'color.surface.subtle': '#F3F4F6',
      'color.text.primary': '#0B0B0B',
      'color.text.secondary': '#4B5563',
      'color.action.brand': '#0B0B0B',
    },
    dark: <String, String>{
      'color.surface.primary': '#0B0B0B',
      'color.surface.subtle': '#111827',
      'color.text.primary': '#FFFFFF',
      'color.text.secondary': '#D1D5DB',
      'color.action.brand': '#0B0B0B',
    },
  ),
};
