import 'schema_compatibility.dart';

final class RuntimeCapabilityProfile {
  const RuntimeCapabilityProfile({
    required this.runtimeApi,
    required this.capabilities,
  });

  final int runtimeApi;
  final Set<String> capabilities;
}

/// Enforces optional `meta` requirements:
/// - `meta.minRuntimeApi`: int
/// - `meta.requiresCapabilities`: list of strings
final class CapabilitySchemaCompatibilityChecker
    implements SchemaCompatibilityChecker {
  const CapabilitySchemaCompatibilityChecker({
    required this.profile,
    required this.inner,
  });

  final RuntimeCapabilityProfile profile;
  final SchemaCompatibilityChecker inner;

  @override
  CompatibilityResult check(Map<String, Object?> document) {
    final base = inner.check(document);
    if (!base.isSupported) return base;

    final metaRaw = document['meta'];
    if (metaRaw is! Map) return base;
    final meta = Map<String, Object?>.from(metaRaw.cast<String, Object?>());

    int? asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final minRuntimeApi = asInt(meta['minRuntimeApi']);
    if (minRuntimeApi != null && minRuntimeApi > profile.runtimeApi) {
      return CompatibilityResult(
        isSupported: false,
        reason:
            'Unsupported runtimeApi=${profile.runtimeApi}; requires minRuntimeApi=$minRuntimeApi',
      );
    }

    final requiresRaw = meta['requiresCapabilities'];
    if (requiresRaw is List) {
      for (final cap in requiresRaw.whereType<String>()) {
        if (cap.isEmpty) continue;
        if (!profile.capabilities.contains(cap)) {
          return CompatibilityResult(
            isSupported: false,
            reason: 'Missing required capability: $cap',
          );
        }
      }
    }

    return base;
  }
}
