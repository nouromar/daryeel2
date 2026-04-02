import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = SchemaCompatibilityPolicy(
    supportedSchemaVersions: {'1.0'},
    supportedProducts: {'customer_app'},
    supportedThemeIds: {'customer-default'},
    supportedThemeModes: {'light', 'dark'},
    requireRootNode: true,
  );

  const baseChecker = PolicySchemaCompatibilityChecker(policy: policy);

  test('Capability checker passes when meta is absent', () {
    const checker = CapabilitySchemaCompatibilityChecker(
      profile:
          RuntimeCapabilityProfile(runtimeApi: 1, capabilities: <String>{}),
      inner: baseChecker,
    );

    final result = checker.check(const <String, Object?>{
      'schemaVersion': '1.0',
      'id': 'customer_home',
      'documentType': 'screen',
      'product': 'customer_app',
      'themeId': 'customer-default',
      'themeMode': 'light',
      'root': <String, Object?>{'type': 'Text'},
    });

    expect(result.isSupported, isTrue);
  });

  test('Capability checker enforces meta.minRuntimeApi', () {
    const checker = CapabilitySchemaCompatibilityChecker(
      profile:
          RuntimeCapabilityProfile(runtimeApi: 1, capabilities: <String>{}),
      inner: baseChecker,
    );

    final result = checker.check(const <String, Object?>{
      'schemaVersion': '1.0',
      'id': 'customer_home',
      'documentType': 'screen',
      'product': 'customer_app',
      'themeId': 'customer-default',
      'themeMode': 'light',
      'meta': <String, Object?>{
        'minRuntimeApi': 2,
      },
      'root': <String, Object?>{'type': 'Text'},
    });

    expect(result.isSupported, isFalse);
    expect(result.reason, contains('minRuntimeApi'));
  });

  test('Capability checker enforces meta.requiresCapabilities', () {
    const checker = CapabilitySchemaCompatibilityChecker(
      profile: RuntimeCapabilityProfile(
        runtimeApi: 10,
        capabilities: <String>{'refNodes'},
      ),
      inner: baseChecker,
    );

    final result = checker.check(const <String, Object?>{
      'schemaVersion': '1.0',
      'id': 'customer_home',
      'documentType': 'screen',
      'product': 'customer_app',
      'themeId': 'customer-default',
      'themeMode': 'light',
      'meta': <String, Object?>{
        'requiresCapabilities': <String>['refNodes', 'actions.submit_form.v1'],
      },
      'root': <String, Object?>{'type': 'Text'},
    });

    expect(result.isSupported, isFalse);
    expect(result.reason, contains('Missing required capability'));
  });

  test('Capability checker accepts when required capabilities are supported',
      () {
    const checker = CapabilitySchemaCompatibilityChecker(
      profile: RuntimeCapabilityProfile(
        runtimeApi: 10,
        capabilities: <String>{'refNodes', 'actions.submit_form.v1'},
      ),
      inner: baseChecker,
    );

    final result = checker.check(const <String, Object?>{
      'schemaVersion': '1.0',
      'id': 'customer_home',
      'documentType': 'screen',
      'product': 'customer_app',
      'themeId': 'customer-default',
      'themeMode': 'light',
      'meta': <String, Object?>{
        'minRuntimeApi': 2,
        'requiresCapabilities': <String>['refNodes', 'actions.submit_form.v1'],
      },
      'root': <String, Object?>{'type': 'Text'},
    });

    expect(result.isSupported, isTrue);
  });
}
