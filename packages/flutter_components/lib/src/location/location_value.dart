typedef LocationValue = Map<String, Object?>;

LocationValue? coerceLocationValue(Object? raw) {
  if (raw is! Map) return null;
  return raw.map((k, v) => MapEntry(k.toString(), v)).cast<String, Object?>();
}

String locationText(LocationValue? value) {
  final raw = value?['text'];
  if (raw is String) return raw.trim();
  return '';
}

LocationValue buildManualLocationValue(String text) {
  return <String, Object?>{
    'text': text,
    'lat': null,
    'lng': null,
    'accuracy_m': null,
    'place_id': null,
    'region_id': null,
    'source': 'manual',
  };
}
