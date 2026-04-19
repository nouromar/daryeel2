import 'package:flutter_runtime/flutter_runtime.dart';

class CustomerSchemaCompatibilityChecker implements SchemaCompatibilityChecker {
  const CustomerSchemaCompatibilityChecker({this.overlay});

  final SchemaCompatibilityPolicyOverlay? overlay;

  static const _supportedSchemaVersion = '1.0';
  static const _supportedProduct = 'customer_app';
  static const _supportedThemes = {
    'customer-default',
    'custome-black-white-clear',
  };
  static const _supportedThemeModes = {'light', 'dark'};

  @override
  CompatibilityResult check(Map<String, Object?> document) {
    const base = SchemaCompatibilityPolicy(
      supportedSchemaVersions: {_supportedSchemaVersion},
      supportedProducts: {_supportedProduct},
      supportedThemeIds: _supportedThemes,
      supportedThemeModes: _supportedThemeModes,
      requireRootNode: true,
    );

    final policy = overlay == null
        ? base
        : applyRestrictivePolicyOverlay(base, overlay!);

    return PolicySchemaCompatibilityChecker(policy: policy).check(document);
  }
}
