/// Centralized, hard security budgets for schema-driven UI.
///
/// These are intended to be conservative defaults that prevent denial-of-service
/// via oversized documents or pathological reference graphs.
///
/// Notes:
/// - Server-side validation (schema-service) should enforce equal-or-stricter
///   budgets during CI/validation.
/// - Clients enforce these again at runtime because remote inputs are untrusted.
class SecurityBudgets {
  const SecurityBudgets._();

  /// Max UTF-8 bytes for a single schema document JSON.
  static const int maxSchemaJsonBytes = 256 * 1024;

  /// Max nodes allowed in a single resolved screen document.
  ///
  /// Count includes both component nodes and ref nodes.
  static const int maxNodesPerDocument = 5000;

  /// Max reference resolution depth.
  static const int maxRefDepth = 32;

  /// Max unique fragment refs that may be loaded for a screen.
  static const int maxFragmentsPerScreen = 200;
}
