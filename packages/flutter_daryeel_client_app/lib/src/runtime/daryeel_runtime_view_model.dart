import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

enum ScreenLoadSource { bundled, remote, fallback }

class LoadedScreen {
  const LoadedScreen({
    required this.bundle,
    required this.source,
    this.schemaLadderSource,
    this.schemaLadderReason,
    this.errorMessage,
    this.schema,
    this.parseErrors = const <SchemaParseError>[],
    this.refErrors = const <RefResolutionError>[],
    this.configSnapshotId,
    this.enabledFeatureFlags = const <String>{},
    required this.theme,
    required this.darkTheme,
    required this.themeMode,
    this.usedRemoteTheme = false,
    this.themeSource,
    this.themeDocId,
  });

  final SchemaBundle bundle;
  final ScreenLoadSource source;
  final SchemaLadderSource? schemaLadderSource;
  final SchemaLadderReason? schemaLadderReason;
  final String? errorMessage;
  final ScreenSchema? schema;
  final List<SchemaParseError> parseErrors;
  final List<RefResolutionError> refErrors;
  final String? configSnapshotId;
  final Set<String> enabledFeatureFlags;

  final ThemeData theme;
  final ThemeData darkTheme;
  final ThemeMode themeMode;
  final bool usedRemoteTheme;
  final ThemeLadderSource? themeSource;
  final String? themeDocId;

  LoadedScreen copyWith({
    SchemaLadderSource? schemaLadderSource,
    SchemaLadderReason? schemaLadderReason,
  }) {
    return LoadedScreen(
      bundle: bundle,
      source: source,
      schemaLadderSource: schemaLadderSource ?? this.schemaLadderSource,
      schemaLadderReason: schemaLadderReason ?? this.schemaLadderReason,
      errorMessage: errorMessage,
      schema: schema,
      parseErrors: parseErrors,
      refErrors: refErrors,
      configSnapshotId: configSnapshotId,
      enabledFeatureFlags: enabledFeatureFlags,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      usedRemoteTheme: usedRemoteTheme,
      themeSource: themeSource,
      themeDocId: themeDocId,
    );
  }
}

class DaryeelRuntimeViewModel {
  const DaryeelRuntimeViewModel({
    required this.screen,
    required this.diagnostics,
    required this.actionDispatcher,
    required this.actionPolicy,
    required this.visibility,
    required this.rendererDiagnosticsContext,
  });

  final LoadedScreen screen;
  final RuntimeDiagnostics diagnostics;
  final SchemaActionDispatcher actionDispatcher;
  final SchemaActionPolicy actionPolicy;
  final SchemaVisibilityContext visibility;
  final Map<String, Object?> rendererDiagnosticsContext;
}
