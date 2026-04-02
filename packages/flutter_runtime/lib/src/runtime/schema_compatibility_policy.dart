import 'schema_compatibility.dart';

/// A simple, declarative compatibility allowlist for schema bundles.
///
/// Any `supported* == null` means "allow all" for that dimension.
final class SchemaCompatibilityPolicy {
  const SchemaCompatibilityPolicy({
    required this.supportedSchemaVersions,
    this.supportedProducts,
    this.supportedThemeIds,
    this.supportedThemeModes,
    this.requireRootNode = true,
  });

  final Set<String> supportedSchemaVersions;
  final Set<String>? supportedProducts;
  final Set<String>? supportedThemeIds;
  final Set<String>? supportedThemeModes;
  final bool requireRootNode;
}

/// A restrictive overlay that can only tighten a [SchemaCompatibilityPolicy].
///
/// Any non-null set further restricts (intersects) the base policy.
final class SchemaCompatibilityPolicyOverlay {
  const SchemaCompatibilityPolicyOverlay({
    this.supportedSchemaVersions,
    this.supportedProducts,
    this.supportedThemeIds,
    this.supportedThemeModes,
    this.requireRootNode,
  });

  final Set<String>? supportedSchemaVersions;
  final Set<String>? supportedProducts;
  final Set<String>? supportedThemeIds;
  final Set<String>? supportedThemeModes;
  final bool? requireRootNode;
}

SchemaCompatibilityPolicy applyRestrictivePolicyOverlay(
  SchemaCompatibilityPolicy base,
  SchemaCompatibilityPolicyOverlay overlay,
) {
  Set<String> intersectRequired(Set<String> a, Set<String> b) {
    return a.intersection(b);
  }

  Set<String>? intersectOptional(Set<String>? a, Set<String>? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.intersection(b);
  }

  final supportedSchemaVersions = overlay.supportedSchemaVersions == null
      ? base.supportedSchemaVersions
      : intersectRequired(base.supportedSchemaVersions,
          overlay.supportedSchemaVersions ?? const <String>{});

  return SchemaCompatibilityPolicy(
    supportedSchemaVersions: supportedSchemaVersions,
    supportedProducts:
        intersectOptional(base.supportedProducts, overlay.supportedProducts),
    supportedThemeIds:
        intersectOptional(base.supportedThemeIds, overlay.supportedThemeIds),
    supportedThemeModes: intersectOptional(
        base.supportedThemeModes, overlay.supportedThemeModes),
    requireRootNode: base.requireRootNode || (overlay.requireRootNode == true),
  );
}

/// Enforces a [SchemaCompatibilityPolicy] against a schema document.
final class PolicySchemaCompatibilityChecker
    implements SchemaCompatibilityChecker {
  const PolicySchemaCompatibilityChecker({required this.policy});

  final SchemaCompatibilityPolicy policy;

  @override
  CompatibilityResult check(Map<String, Object?> document) {
    final schemaVersion = document['schemaVersion'];
    if (schemaVersion is! String || schemaVersion.isEmpty) {
      return const CompatibilityResult(
        isSupported: false,
        reason: 'Missing schemaVersion',
      );
    }
    if (!policy.supportedSchemaVersions.contains(schemaVersion)) {
      return CompatibilityResult(
        isSupported: false,
        reason: 'Unsupported schema version: $schemaVersion',
      );
    }

    final product = document['product'];
    if (product is! String || product.isEmpty) {
      return const CompatibilityResult(
        isSupported: false,
        reason: 'Missing product',
      );
    }
    final allowedProducts = policy.supportedProducts;
    if (allowedProducts != null && !allowedProducts.contains(product)) {
      return CompatibilityResult(
        isSupported: false,
        reason: 'Unsupported product: $product',
      );
    }

    final themeId = document['themeId'];
    if (themeId is! String || themeId.isEmpty) {
      return const CompatibilityResult(
        isSupported: false,
        reason: 'Missing themeId',
      );
    }
    final allowedThemeIds = policy.supportedThemeIds;
    if (allowedThemeIds != null && !allowedThemeIds.contains(themeId)) {
      return CompatibilityResult(
        isSupported: false,
        reason: 'Unsupported themeId: $themeId',
      );
    }

    final themeMode = document['themeMode'];
    if (themeMode is String && themeMode.isNotEmpty) {
      final allowedThemeModes = policy.supportedThemeModes;
      if (allowedThemeModes != null && !allowedThemeModes.contains(themeMode)) {
        return CompatibilityResult(
          isSupported: false,
          reason: 'Unsupported theme mode: $themeMode',
        );
      }
    }

    if (policy.requireRootNode) {
      final root = document['root'];
      if (root is! Map) {
        return const CompatibilityResult(
          isSupported: false,
          reason: 'Schema root node is missing',
        );
      }
    }

    return const CompatibilityResult(isSupported: true);
  }
}
