import 'package:flutter/material.dart';

import 'theme_document.dart';

ThemeMode resolveThemeMode({required String? themeMode}) {
  return themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
}

ThemeData resolveThemeData({required ThemeDocument theme}) {
  final isDark = theme.themeMode == 'dark';
  final brightness = isDark ? Brightness.dark : Brightness.light;
  final primary = _parseHex(theme.tokens['color.action.brand'] as String?);
  final surface = _parseHex(theme.tokens['color.surface.primary'] as String?);
  final surfaceSubtle = _parseHex(
    theme.tokens['color.surface.subtle'] as String?,
  );
  final textPrimary = _parseHex(theme.tokens['color.text.primary'] as String?);
  final textSecondary = _parseHex(
    theme.tokens['color.text.secondary'] as String?,
  );

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

Color _parseHex(String? value) {
  if (value == null) {
    return const Color(0xFF0F766E);
  }
  final sanitized = value.replaceFirst('#', '');
  return Color(int.parse('FF$sanitized', radix: 16));
}
