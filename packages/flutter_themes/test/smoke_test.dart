import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_themes/flutter_themes.dart';

void main() {
  test('flutter_themes smoke', () {
    // Verifies the package can be imported, compiled, and basic APIs behave.
    expect(resolveThemeMode(themeMode: 'dark'), ThemeMode.dark);
  });
}
