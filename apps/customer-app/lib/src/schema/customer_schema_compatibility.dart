import 'package:flutter_runtime/flutter_runtime.dart';

class CustomerSchemaCompatibilityChecker implements SchemaCompatibilityChecker {
  const CustomerSchemaCompatibilityChecker();

  static const _supportedSchemaVersion = '1.0';
  static const _supportedProduct = 'customer_app';
  static const _supportedThemes = {'customer-default'};
  static const _supportedThemeModes = {'light', 'dark'};

  @override
  CompatibilityResult check(Map<String, Object?> document) {
    final schemaVersion = document['schemaVersion'] as String?;
    if (schemaVersion != _supportedSchemaVersion) {
      return CompatibilityResult(
        isSupported: false,
        reason: 'Unsupported schema version: $schemaVersion',
      );
    }

    final product = document['product'] as String?;
    if (product != _supportedProduct) {
      return CompatibilityResult(
        isSupported: false,
        reason: 'Unsupported product target: $product',
      );
    }

    final themeId = document['themeId'] as String?;
    if (themeId == null || !_supportedThemes.contains(themeId)) {
      return CompatibilityResult(
        isSupported: false,
        reason: 'Unsupported theme id: $themeId',
      );
    }

    final themeMode = document['themeMode'] as String?;
    if (themeMode != null && !_supportedThemeModes.contains(themeMode)) {
      return CompatibilityResult(
        isSupported: false,
        reason: 'Unsupported theme mode: $themeMode',
      );
    }

    if (document['root'] is! Map) {
      return const CompatibilityResult(
        isSupported: false,
        reason: 'Schema root node is missing',
      );
    }

    return const CompatibilityResult(isSupported: true);
  }
}
