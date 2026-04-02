import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PolicySchemaCompatibilityChecker enforces allowlists', () {
    const checker = PolicySchemaCompatibilityChecker(
      policy: SchemaCompatibilityPolicy(
        supportedSchemaVersions: {'1.0'},
        supportedProducts: {'customer_app'},
        supportedThemeIds: {'customer-default'},
        supportedThemeModes: {'light', 'dark'},
      ),
    );

    final ok = checker.check(const <String, Object?>{
      'schemaVersion': '1.0',
      'product': 'customer_app',
      'themeId': 'customer-default',
      'themeMode': 'light',
      'root': <String, Object?>{'type': 'Text'},
    });
    expect(ok.isSupported, isTrue);

    final badVersion = checker.check(const <String, Object?>{
      'schemaVersion': '999.0',
      'product': 'customer_app',
      'themeId': 'customer-default',
      'root': <String, Object?>{'type': 'Text'},
    });
    expect(badVersion.isSupported, isFalse);
    expect(badVersion.reason, contains('Unsupported schema version'));

    final badThemeMode = checker.check(const <String, Object?>{
      'schemaVersion': '1.0',
      'product': 'customer_app',
      'themeId': 'customer-default',
      'themeMode': 'sepia',
      'root': <String, Object?>{'type': 'Text'},
    });
    expect(badThemeMode.isSupported, isFalse);
    expect(badThemeMode.reason, contains('Unsupported theme mode'));

    final missingRoot = checker.check(const <String, Object?>{
      'schemaVersion': '1.0',
      'product': 'customer_app',
      'themeId': 'customer-default',
    });
    expect(missingRoot.isSupported, isFalse);
    expect(missingRoot.reason, contains('Schema root node is missing'));
  });
}
