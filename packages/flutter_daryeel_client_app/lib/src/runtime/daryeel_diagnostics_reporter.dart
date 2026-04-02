import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

import '../telemetry/http_remote_diagnostics_transport.dart';

class DaryeelDiagnosticsReporter {
  DaryeelDiagnosticsReporter({
    required this.appId,
    required DiagnosticsSink? diagnosticsSinkOverride,
    List<DiagnosticsSink> additionalSinks = const <DiagnosticsSink>[],
  }) : _diagnosticsSinkOverride = diagnosticsSinkOverride,
       _additionalSinks = additionalSinks;

  final String appId;

  static final Random _random = Random.secure();

  static String randomHexId(int bytes) {
    final sb = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      final v = _random.nextInt(256);
      sb.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  final DiagnosticsSink? _diagnosticsSinkOverride;
  final List<DiagnosticsSink> _additionalSinks;

  late final String sessionId = randomHexId(16);

  /// Correlates all diagnostics emitted during a single screen load.
  late final String screenLoadId = randomHexId(12);

  String? activeConfigSnapshotId;

  Map<String, String> buildCorrelationHeaders({
    String? schemaVersion,
    String? configSnapshotId,
  }) {
    final effectiveConfigSnapshotId =
        configSnapshotId ?? activeConfigSnapshotId;
    return <String, String>{
      'x-request-id': randomHexId(16),
      'x-daryeel-session-id': sessionId,
      if (schemaVersion != null && schemaVersion.isNotEmpty)
        'x-daryeel-schema-version': schemaVersion,
      if (effectiveConfigSnapshotId?.isNotEmpty ?? false)
        'x-daryeel-config-snapshot': effectiveConfigSnapshotId!,
    };
  }

  DiagnosticsSink buildDiagnosticsSink({
    Uri? telemetryEndpoint,
    required bool enableRemoteIngest,
  }) {
    final override = _diagnosticsSinkOverride;
    if (override != null) return override;

    final sinks = <DiagnosticsSink>[..._additionalSinks];
    if (kDebugMode) {
      sinks.add(const DebugPrintDiagnosticsSink(includePayload: true));
    }

    if (enableRemoteIngest && telemetryEndpoint != null) {
      sinks.add(
        RemoteDiagnosticsSink(
          endpoint: telemetryEndpoint,
          transport: HttpRemoteDiagnosticsTransport(),
          headersProvider: () => buildCorrelationHeaders(),
        ),
      );
    }

    if (sinks.isEmpty) return const NoopDiagnosticsSink();
    if (sinks.length == 1) return sinks.single;
    return MultiDiagnosticsSink(sinks);
  }

  DiagnosticsConfig diagnosticsConfigFromSnapshot({
    required int? dedupeTtlSeconds,
    required int? maxInfoPerSession,
    required int? maxWarnPerSession,
  }) {
    int clampInt(int v, int min, int max) {
      if (v < min) return min;
      if (v > max) return max;
      return v;
    }

    final dedupeTtl = dedupeTtlSeconds == null
        ? const Duration(seconds: 60)
        : Duration(seconds: clampInt(dedupeTtlSeconds, 5, 600));

    return DiagnosticsConfig(
      enableDebug: kDebugMode,
      dedupeTtl: dedupeTtl,
      maxInfoPerSession: maxInfoPerSession == null
          ? 30
          : clampInt(maxInfoPerSession, 0, 500),
      maxWarnPerSession: maxWarnPerSession == null
          ? 50
          : clampInt(maxWarnPerSession, 0, 500),
    );
  }

  Uri? resolveTelemetryEndpoint({
    required String? telemetryIngestUrl,
    required String fallbackBaseUrl,
  }) {
    if (telemetryIngestUrl != null && telemetryIngestUrl.isNotEmpty) {
      return Uri.tryParse(telemetryIngestUrl);
    }
    if (fallbackBaseUrl.isEmpty) return null;
    final normalized = fallbackBaseUrl.endsWith('/')
        ? fallbackBaseUrl.substring(0, fallbackBaseUrl.length - 1)
        : fallbackBaseUrl;
    return Uri.tryParse('$normalized/telemetry/diagnostics');
  }

  Map<String, Object?> contextForRequest(
    RuntimeScreenRequest req, {
    String? configSnapshotId,
  }) {
    return <String, Object?>{
      'app': <String, Object?>{
        'appId': appId,
        'buildFlavor': kDebugMode ? 'dev' : 'prod',
      },
      'screenLoad': <String, Object?>{'id': screenLoadId},
      'schema': <String, Object?>{
        'screenId': req.screenId,
        'product': req.product,
        if (req.service != null) 'serviceSlug': req.service,
      },
      if (configSnapshotId != null && configSnapshotId.isNotEmpty)
        'config': <String, Object?>{'snapshotId': configSnapshotId},
    };
  }

  Map<String, Object?> contextForBundle(
    SchemaBundle bundle,
    RuntimeScreenRequest req,
    String? configSnapshotId,
  ) {
    final base = contextForRequest(req, configSnapshotId: configSnapshotId);
    return <String, Object?>{
      ...base,
      'schema': <String, Object?>{
        ...(base['schema'] as Map<String, Object?>),
        'bundleId': bundle.schemaId,
        'bundleVersion': bundle.schemaVersion,
        'schemaFormatVersion':
            bundle.document['schemaVersion'] as String? ?? bundle.schemaVersion,
      },
    };
  }

  void emitSchemaSourceUsed(
    RuntimeDiagnostics diagnostics,
    RuntimeScreenRequest req, {
    required SchemaLadderSource source,
    String? docId,
    String? pinnedDocId,
    SchemaLadderReason? reason,
    String? configSnapshotId,
  }) {
    diagnostics.emit(
      DiagnosticEvent(
        eventName: SchemaLadderEventNames.sourceUsed,
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.metric,
        fingerprint:
            '${SchemaLadderEventNames.sourceUsed}:${req.product}:${req.screenId}:${source.wireValue}',
        context: contextForRequest(req, configSnapshotId: configSnapshotId),
        payload: <String, Object?>{
          'source': source.wireValue,
          if (docId != null && docId.isNotEmpty) 'docId': docId,
          if (pinnedDocId != null && pinnedDocId.isNotEmpty)
            'pinnedDocId': pinnedDocId,
          if (reason != null) 'reasonCode': reason.wireValue,
        },
      ),
    );
  }

  void emitSchemaFallback(
    RuntimeDiagnostics diagnostics,
    RuntimeScreenRequest req, {
    required SchemaLadderSource fromSource,
    required SchemaLadderSource toSource,
    required SchemaLadderReason reason,
    String? errorType,
    String? configSnapshotId,
  }) {
    diagnostics.emit(
      DiagnosticEvent(
        eventName: SchemaLadderEventNames.fallback,
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            '${SchemaLadderEventNames.fallback}:${req.product}:${req.screenId}:${reason.wireValue}',
        context: contextForRequest(req, configSnapshotId: configSnapshotId),
        payload: <String, Object?>{
          'fromSource': fromSource.wireValue,
          'toSource': toSource.wireValue,
          'reasonCode': reason.wireValue,
          if (errorType != null && errorType.isNotEmpty) 'errorType': errorType,
        },
      ),
    );
  }

  void emitSchemaPinCleared(
    RuntimeDiagnostics diagnostics,
    RuntimeScreenRequest req, {
    required String pinnedDocId,
    required SchemaLadderReason reason,
    String? configSnapshotId,
  }) {
    diagnostics.emit(
      DiagnosticEvent(
        eventName: SchemaLadderEventNames.pinCleared,
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            '${SchemaLadderEventNames.pinCleared}:${req.product}:${req.screenId}:$pinnedDocId',
        context: contextForRequest(req, configSnapshotId: configSnapshotId),
        payload: <String, Object?>{
          'pinnedDocId': pinnedDocId,
          'reasonCode': reason.wireValue,
        },
      ),
    );
  }

  void emitSchemaPinPromoted(
    RuntimeDiagnostics diagnostics,
    RuntimeScreenRequest req, {
    required String docId,
    String? configSnapshotId,
  }) {
    diagnostics.emit(
      DiagnosticEvent(
        eventName: SchemaLadderEventNames.pinPromoted,
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.metric,
        fingerprint:
            '${SchemaLadderEventNames.pinPromoted}:${req.product}:${req.screenId}:$docId',
        context: contextForRequest(req, configSnapshotId: configSnapshotId),
        payload: <String, Object?>{
          'docId': docId,
          'promotedFrom': SchemaLadderSource.selector.wireValue,
        },
      ),
    );
  }

  void emitThemeSourceUsed(
    RuntimeDiagnostics diagnostics,
    RuntimeScreenRequest req, {
    required String themeId,
    required String themeMode,
    required ThemeLadderSource source,
    String? docId,
    String? configSnapshotId,
  }) {
    diagnostics.emit(
      DiagnosticEvent(
        eventName: ThemeLadderEventNames.sourceUsed,
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.metric,
        fingerprint:
            '${ThemeLadderEventNames.sourceUsed}:${req.product}:${req.screenId}:${themeId}:${themeMode}:${source.wireValue}',
        context: contextForRequest(req, configSnapshotId: configSnapshotId),
        payload: <String, Object?>{
          'themeId': themeId,
          'themeMode': themeMode,
          'source': source.wireValue,
          if (docId != null && docId.isNotEmpty) 'docId': docId,
        },
      ),
    );
  }

  void emitThemeFallbackToLocal(
    RuntimeDiagnostics diagnostics,
    RuntimeScreenRequest req, {
    required String themeId,
    required String themeMode,
    required ThemeLadderReason reason,
    String? errorType,
    String? configSnapshotId,
  }) {
    diagnostics.emit(
      DiagnosticEvent(
        eventName: ThemeLadderEventNames.fallbackToLocal,
        severity: DiagnosticSeverity.warn,
        kind: DiagnosticKind.diagnostic,
        fingerprint:
            '${ThemeLadderEventNames.fallbackToLocal}:${req.product}:${req.screenId}:${themeId}:${themeMode}:${reason.wireValue}',
        context: contextForRequest(req, configSnapshotId: configSnapshotId),
        payload: <String, Object?>{
          'themeId': themeId,
          'themeMode': themeMode,
          'reasonCode': reason.wireValue,
          if (errorType != null && errorType.isNotEmpty) 'errorType': errorType,
        },
      ),
    );
  }

  void emitScreenLoadSummary(
    RuntimeDiagnostics diagnostics,
    RuntimeScreenRequest req,
    SchemaBundle bundle, {
    required ThemeLadderSource finalThemeSource,
    required String? themeDocId,
    required bool usedRemoteTheme,
    required int parseErrorCount,
    required int refErrorCount,
    required SchemaLadderSource finalSchemaSource,
    required SchemaLadderReason? finalSchemaReason,
    required String? schemaDocId,
    required int attemptCount,
    required int fallbackCount,
    required int totalLoadMs,
    String? configSnapshotId,
  }) {
    diagnostics.emit(
      DiagnosticEvent(
        eventName: 'runtime.screen_load.summary',
        severity: DiagnosticSeverity.info,
        kind: DiagnosticKind.metric,
        fingerprint:
            'runtime.screen_load.summary:${req.product}:${req.screenId}:${finalSchemaSource.wireValue}',
        context: contextForBundle(bundle, req, configSnapshotId),
        payload: <String, Object?>{
          'screenLoadId': screenLoadId,
          'finalSchemaSource': finalSchemaSource.wireValue,
          if (finalSchemaReason != null)
            'finalSchemaReasonCode': finalSchemaReason.wireValue,
          if (schemaDocId != null && schemaDocId.isNotEmpty)
            'schemaDocId': schemaDocId,
          'parseErrorCount': parseErrorCount,
          'refErrorCount': refErrorCount,
          'usedRemoteTheme': usedRemoteTheme,
          'finalThemeSource': finalThemeSource.wireValue,
          if (themeDocId != null && themeDocId.isNotEmpty)
            'themeDocId': themeDocId,
          'attemptCount': attemptCount,
          'fallbackCount': fallbackCount,
          'totalLoadMs': totalLoadMs,
        },
      ),
    );
  }
}
