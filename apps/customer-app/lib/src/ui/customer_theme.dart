import 'package:flutter/material.dart';

ThemeData resolveCustomerTheme(
  Map<String, Object?> document, {
  String? overrideMode,
}) {
  final mode = overrideMode ?? document['themeMode'] as String? ?? 'light';
  final tokens = mode == 'dark' ? _darkTokens : _lightTokens;
  final primary = _parseHex(tokens['color.action.brand']!);
  final surface = _parseHex(tokens['color.surface.primary']!);
  final surfaceSubtle = _parseHex(tokens['color.surface.subtle']!);
  final textPrimary = _parseHex(tokens['color.text.primary']!);
  final textSecondary = _parseHex(tokens['color.text.secondary']!);
  final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;

  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      secondary: primary,
      onSecondary: Colors.white,
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
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        color: textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
      bodyMedium: TextStyle(color: textSecondary, fontSize: 16, height: 1.4),
      titleMedium: TextStyle(
        color: textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
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

const _lightTokens = <String, String>{
  'color.surface.primary': '#FFFFFF',
  'color.surface.subtle': '#F8FAFC',
  'color.text.primary': '#0F172A',
  'color.text.secondary': '#475569',
  'color.action.brand': '#0F766E',
};

const _darkTokens = <String, String>{
  'color.surface.primary': '#0F172A',
  'color.surface.subtle': '#111827',
  'color.text.primary': '#F8FAFC',
  'color.text.secondary': '#CBD5E1',
  'color.action.brand': '#14B8A6',
};
