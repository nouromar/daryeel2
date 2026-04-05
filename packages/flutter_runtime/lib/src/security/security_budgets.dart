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

  // -------------------------
  // Query / network budgets
  // -------------------------

  /// Max bytes allowed for a single decoded HTTP response payload.
  ///
  /// Exceeding this budget fails the query closed to avoid large/untrusted
  /// payloads overwhelming memory.
  static const int maxQueryResponseBytes = 512 * 1024;

  /// Hard cap to avoid unbounded in-memory growth for infinite scroll.
  static const int maxItemsPerPagedQuery = 1000;

  // -------------------------
  // Diagnostics budgets
  // -------------------------

  /// Maximum number of emitted `info` events per session.
  static const int maxInfoDiagnosticsPerSession = 30;

  /// Maximum number of emitted `warn` events per session.
  static const int maxWarnDiagnosticsPerSession = 50;

  /// Maximum number of stored events for in-memory diagnostics sinks.
  static const int maxInMemoryDiagnosticsEvents = 200;

  // -------------------------
  // State budgets
  // -------------------------

  static const int maxStateKeysPerScreen = 200;
  static const int maxStateStringLength = 4 * 1024;

  // -------------------------
  // Form budgets
  // -------------------------

  static const int maxFieldsPerForm = 200;
  static const int maxFormStringLength = 4 * 1024;
  static const int maxFormEnumValues = 200;
  static const int maxFormPatternLength = 512;

  static const int maxFormJsonDepth = 8;
  static const int maxFormJsonNodes = 800;
  static const int maxFormJsonEntriesPerMap = 80;
  static const int maxFormJsonItemsPerList = 200;
  static const int maxFormJsonKeyLength = 80;
}
