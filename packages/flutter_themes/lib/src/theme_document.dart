class ThemeDocument {
  const ThemeDocument({
    required this.themeId,
    required this.themeMode,
    required this.inherits,
    required this.tokens,
  });

  final String themeId;
  final String themeMode;
  final List<String> inherits;
  final Map<String, Object?> tokens;

  static ThemeDocument fromJson(Map<String, Object?> json) {
    final themeId = json['themeId'] as String?;
    final themeMode = json['themeMode'] as String?;
    if (themeId == null || themeMode == null) {
      throw const FormatException('Invalid theme document');
    }
    final inheritsRaw = json['inherits'];
    final tokensRaw = json['tokens'];
    return ThemeDocument(
      themeId: themeId,
      themeMode: themeMode,
      inherits: inheritsRaw is List
          ? inheritsRaw.whereType<String>().toList(growable: false)
          : const <String>[],
      tokens: tokensRaw is Map
          ? Map<String, Object?>.from(tokensRaw.cast<String, Object?>())
          : const <String, Object?>{},
    );
  }
}
