class CompatibilityResult {
  const CompatibilityResult({required this.isSupported, this.reason});

  final bool isSupported;
  final String? reason;
}

abstract class SchemaCompatibilityChecker {
  CompatibilityResult check(Map<String, Object?> document);
}
