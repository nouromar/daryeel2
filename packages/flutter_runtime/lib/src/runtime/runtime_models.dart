class SchemaBundle {
  const SchemaBundle({
    required this.schemaId,
    required this.schemaVersion,
    required this.document,
    this.docId,
  });

  final String schemaId;
  final String schemaVersion;
  final Map<String, Object?> document;

  /// Immutable document identifier (if known).
  ///
  /// When present, the app can use this to pin the exact document version.
  final String? docId;
}

class RuntimeScreenRequest {
  const RuntimeScreenRequest(
      {required this.screenId, required this.product, this.service});

  final String screenId;
  final String product;
  final String? service;
}
