class SchemaBundle {
  const SchemaBundle({required this.schemaId, required this.schemaVersion, required this.document});

  final String schemaId;
  final String schemaVersion;
  final Map<String, Object?> document;
}

class RuntimeScreenRequest {
  const RuntimeScreenRequest({required this.screenId, required this.product, this.service});

  final String screenId;
  final String product;
  final String? service;
}
