/// Shared taxonomy for schema/theme fallback ladder diagnostics.
///
/// Keep these stable: dashboards and alerts will rely on them.

enum SchemaLadderSource {
  pinnedImmutable,
  cachedPinned,
  selector,
  bundled,
  bundledFallback,
}

extension SchemaLadderSourceWire on SchemaLadderSource {
  String get wireValue {
    return switch (this) {
      SchemaLadderSource.pinnedImmutable => 'pinned_immutable',
      SchemaLadderSource.cachedPinned => 'cached_pinned',
      SchemaLadderSource.selector => 'selector',
      SchemaLadderSource.bundled => 'bundled',
      SchemaLadderSource.bundledFallback => 'bundled_fallback',
    };
  }
}

enum SchemaLadderReason {
  pinnedException,
  pinnedIncompatible,
  noRemoteBaseUrl,
  cachedPinnedMissing,
  cachedPinnedInvalid,
  cachedPinnedException,
  selectorIncompatible,
  selectorException,
}

extension SchemaLadderReasonWire on SchemaLadderReason {
  String get wireValue {
    return switch (this) {
      SchemaLadderReason.pinnedException => 'pinned_exception',
      SchemaLadderReason.pinnedIncompatible => 'pinned_incompatible',
      SchemaLadderReason.noRemoteBaseUrl => 'no_remote_base_url',
      SchemaLadderReason.cachedPinnedMissing => 'cached_pinned_missing',
      SchemaLadderReason.cachedPinnedInvalid => 'cached_pinned_invalid',
      SchemaLadderReason.cachedPinnedException => 'cached_pinned_exception',
      SchemaLadderReason.selectorIncompatible => 'selector_incompatible',
      SchemaLadderReason.selectorException => 'selector_exception',
    };
  }
}

abstract final class SchemaLadderEventNames {
  static const String sourceUsed = 'runtime.schema.ladder.source_used';
  static const String fallback = 'runtime.schema.ladder.fallback';
  static const String pinCleared = 'runtime.schema.ladder.pin_cleared';
  static const String pinPromoted = 'runtime.schema.ladder.pin_promoted';
}

enum ThemeLadderSource {
  pinnedImmutable,
  cachedPinned,
  selector,
  local,
}

extension ThemeLadderSourceWire on ThemeLadderSource {
  String get wireValue {
    return switch (this) {
      ThemeLadderSource.pinnedImmutable => 'pinned_immutable',
      ThemeLadderSource.cachedPinned => 'cached_pinned',
      ThemeLadderSource.selector => 'selector',
      ThemeLadderSource.local => 'local',
    };
  }
}

enum ThemeLadderReason {
  remoteReturnedNull,
  exception,
  noThemeBaseUrl,
  remoteThemesDisabled,
}

extension ThemeLadderReasonWire on ThemeLadderReason {
  String get wireValue {
    return switch (this) {
      ThemeLadderReason.remoteReturnedNull => 'remote_returned_null',
      ThemeLadderReason.exception => 'exception',
      ThemeLadderReason.noThemeBaseUrl => 'no_theme_base_url',
      ThemeLadderReason.remoteThemesDisabled => 'remote_themes_disabled',
    };
  }
}

abstract final class ThemeLadderEventNames {
  static const String sourceUsed = 'runtime.theme.ladder.source_used';
  static const String fallbackToLocal =
      'runtime.theme.ladder.fallback_to_local';
}
