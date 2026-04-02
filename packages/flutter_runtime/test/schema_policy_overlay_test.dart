import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applyRestrictivePolicyOverlay intersects sets', () {
    const base = SchemaCompatibilityPolicy(
      supportedSchemaVersions: {'1.0', '2.0'},
      supportedProducts: {'a', 'b'},
      supportedThemeIds: {'t1', 't2'},
      supportedThemeModes: {'light', 'dark'},
      requireRootNode: false,
    );

    const overlay = SchemaCompatibilityPolicyOverlay(
      supportedSchemaVersions: {'1.0'},
      supportedProducts: {'b', 'c'},
      supportedThemeIds: {'t2'},
      supportedThemeModes: {'light'},
      requireRootNode: true,
    );

    final merged = applyRestrictivePolicyOverlay(base, overlay);

    expect(merged.supportedSchemaVersions, {'1.0'});
    expect(merged.supportedProducts, {'b'});
    expect(merged.supportedThemeIds, {'t2'});
    expect(merged.supportedThemeModes, {'light'});
    expect(merged.requireRootNode, isTrue);
  });

  test('overlay can introduce restriction when base allows all', () {
    const base = SchemaCompatibilityPolicy(
      supportedSchemaVersions: {'1.0'},
      supportedProducts: null,
      supportedThemeIds: null,
      supportedThemeModes: null,
      requireRootNode: true,
    );

    const overlay = SchemaCompatibilityPolicyOverlay(
      supportedProducts: {'customer_app'},
    );

    final merged = applyRestrictivePolicyOverlay(base, overlay);

    expect(merged.supportedSchemaVersions, {'1.0'});
    expect(merged.supportedProducts, {'customer_app'});
    expect(merged.supportedThemeIds, isNull);
    expect(merged.supportedThemeModes, isNull);
    expect(merged.requireRootNode, isTrue);
  });
}
