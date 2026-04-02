import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../schema/customer_bootstrap_loader.dart';
import '../schema/customer_schema_compatibility.dart';
import '../schema/customer_schema_loader.dart';
import '../schema/fallback_fragment_documents.dart';
import '../schema/fallback_schema_bundle.dart';
import '../telemetry/http_remote_diagnostics_transport.dart';
import '../actions/diagnostics_submit_form_handler.dart';
import '../actions/diagnostics_track_event_handler.dart';
import '../actions/url_launcher_open_url_handler.dart';
import '../ui/customer_component_registry.dart';
import '../ui/customer_theme.dart';
import '../cache/http_json_cache.dart';

enum ScreenLoadSource { bundled, remote, fallback }

class CustomerApp extends StatefulWidget {
  const CustomerApp({
    super.key,
    this.schemaBaseUrl = const String.fromEnvironment('SCHEMA_BASE_URL'),
  });

  final String schemaBaseUrl;

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  static final Random _random = Random.secure();

  static const String _prefsLkgConfigSnapshotJsonKey =
      'customer_app.lkg_config_snapshot_json';

  static String _randomHexId(int bytes) {
    final sb = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      final v = _random.nextInt(256);
      sb.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  late final String _sessionId = _randomHexId(16);

  String? _activeConfigSnapshotId;

  Map<String, String> _buildCorrelationHeaders({
    String? schemaVersion,
    String? configSnapshotId,
  }) {
    final effectiveConfigSnapshotId =
        configSnapshotId ?? _activeConfigSnapshotId;
    return <String, String>{
      'x-request-id': _randomHexId(16),
      'x-daryeel-session-id': _sessionId,
      if (schemaVersion != null && schemaVersion.isNotEmpty)
        'x-daryeel-schema-version': schemaVersion,
      if (effectiveConfigSnapshotId?.isNotEmpty ?? false)
        'x-daryeel-config-snapshot': effectiveConfigSnapshotId!,
    };
  }

  late RuntimeDiagnostics _diagnostics;

  late final SchemaFormStore _formStore = SchemaFormStore();

  @override
  void dispose() {
    _formStore.dispose();
    super.dispose();
  }

  DiagnosticsSink _buildDiagnosticsSink({
    Uri? telemetryEndpoint,
    required bool enableRemoteIngest,
  }) {
    final sinks = <DiagnosticsSink>[];
    if (kDebugMode) {
      sinks.add(const DebugPrintDiagnosticsSink(includePayload: true));
    }

    if (enableRemoteIngest && telemetryEndpoint != null) {
      sinks.add(
        RemoteDiagnosticsSink(
          endpoint: telemetryEndpoint,
          transport: HttpRemoteDiagnosticsTransport(),
          headersProvider: () => _buildCorrelationHeaders(),
        ),
      );
    }

    if (sinks.isEmpty) return const NoopDiagnosticsSink();
    if (sinks.length == 1) return sinks.single;
    return MultiDiagnosticsSink(sinks);
  }

  late final Future<_LoadedScreen> _screenFuture = _loadScreen();

  Map<String, Object?> _diagnosticsContextForRequest(
    RuntimeScreenRequest req, {
    String? configSnapshotId,
  }) {
    return <String, Object?>{
      'app': <String, Object?>{
        'appId': 'customer-app',
        'buildFlavor': kDebugMode ? 'dev' : 'prod',
      },
      'schema': <String, Object?>{
        'screenId': req.screenId,
        'product': req.product,
        if (req.service != null) 'serviceSlug': req.service,
      },
      if (configSnapshotId != null && configSnapshotId.isNotEmpty)
        'config': <String, Object?>{'snapshotId': configSnapshotId},
    };
  }

  Map<String, Object?> _diagnosticsContextForBundle(
    SchemaBundle bundle,
    RuntimeScreenRequest req,
    String? configSnapshotId,
  ) {
    final base = _diagnosticsContextForRequest(
      req,
      configSnapshotId: configSnapshotId,
    );
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

  Future<_LoadedScreen> _loadScreen() async {
    const product = 'customer_app';
    final compatibilityChecker = CustomerSchemaCompatibilityChecker();

    final prefs = await SharedPreferences.getInstance();
    var httpCache = HttpJsonCache(prefs: prefs);

    ProductBootstrap? bootstrap;
    ConfigSnapshot? configSnapshot;
    var effectiveSchemaBaseUrl = widget.schemaBaseUrl;
    var initialScreenId = 'customer_home';

    final lkgJson = prefs.getString(_prefsLkgConfigSnapshotJsonKey);
    if (lkgJson != null && lkgJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(lkgJson);
        if (decoded is Map) {
          configSnapshot = ConfigSnapshot.fromJson(
            Map<String, Object?>.from(decoded.cast<String, Object?>()),
          );
          if (configSnapshot.snapshotId.isNotEmpty) {
            _activeConfigSnapshotId = configSnapshot.snapshotId;
          }
        }
      } catch (_) {
        // Ignore corrupt cache.
      }
    }

    if (widget.schemaBaseUrl.isNotEmpty) {
      try {
        final loader = CustomerBootstrapLoader(
          baseUrl: widget.schemaBaseUrl,
          headersProvider: () => _buildCorrelationHeaders(),
          cache: httpCache,
        );
        bootstrap = await loader.loadBootstrap(product: product);
        if (bootstrap.configSnapshotId.isNotEmpty) {
          _activeConfigSnapshotId = bootstrap.configSnapshotId;
        }

        effectiveSchemaBaseUrl =
            bootstrap.schemaServiceBaseUrl ?? widget.schemaBaseUrl;
        initialScreenId = bootstrap.initialScreenId;

        if (bootstrap.configSnapshotId.isNotEmpty) {
          final loadedSnapshot = await loader.loadSnapshot(
            snapshotId: bootstrap.configSnapshotId,
            configBaseUrl: bootstrap.configServiceBaseUrl,
          );
          configSnapshot = loadedSnapshot;
          try {
            await prefs.setString(
              _prefsLkgConfigSnapshotJsonKey,
              jsonEncode(loadedSnapshot.toJson()),
            );
          } catch (_) {
            // Best-effort cache.
          }
        }
      } catch (_) {
        // Best-effort: fall back to hardcoded bootstrap.
      }
    }

    final telemetryEndpoint = _resolveTelemetryEndpoint(
      bootstrap: bootstrap,
      fallbackBaseUrl: widget.schemaBaseUrl,
    );

    final diagnosticsConfig = _diagnosticsConfigFromSnapshot(configSnapshot);
    _diagnostics = BudgetedRuntimeDiagnostics(
      sink: _buildDiagnosticsSink(
        telemetryEndpoint: telemetryEndpoint,
        enableRemoteIngest: configSnapshot?.enableRemoteIngest ?? true,
      ),
      config: diagnosticsConfig,
    );

    var request = RuntimeScreenRequest(
      screenId: initialScreenId,
      product: bootstrap?.product ?? product,
    );

    // Now that the request + diagnostics exist, re-create the cache so it can
    // emit cache-corruption diagnostics.
    httpCache = HttpJsonCache(
      prefs: prefs,
      diagnostics: _diagnostics,
      diagnosticsContext: _diagnosticsContextForRequest(request),
    );

    Future<_LoadedScreen> buildLoadedScreen(
      RuntimeScreenRequest screenRequest,
      SchemaBundle bundle,
      ScreenLoadSource source, {
      String? errorMessage,
      String? configSnapshotId,
      Set<String> enabledFeatureFlagsFromConfig = const <String>{},
    }) async {
      final diagnosticsContext = _diagnosticsContextForBundle(
        bundle,
        screenRequest,
        configSnapshotId,
      );

      final parsed = parseScreenSchemaWithDiagnostics(
        bundle.document,
        diagnostics: _diagnostics,
        diagnosticsContext: diagnosticsContext,
      );
      final schema = parsed.value;
      if (schema == null) {
        return _LoadedScreen(
          bundle: bundle,
          source: source,
          errorMessage: errorMessage,
          parseErrors: parsed.errors,
        );
      }

      final FragmentDocumentLoader fragmentLoader =
          source == ScreenLoadSource.remote
          ? HttpFragmentDocumentLoader(
              baseUrl: effectiveSchemaBaseUrl,
              cache: httpCache,
              headersProvider: () => _buildCorrelationHeaders(
                schemaVersion: '${bundle.schemaId}@${bundle.schemaVersion}',
                configSnapshotId: configSnapshotId,
              ),
            )
          : const InMemoryFragmentDocumentLoader(
              documents: fallbackFragmentDocuments,
            );

      final resolved = await resolveScreenRefsWithDiagnostics(
        schema: schema,
        loader: fragmentLoader,
        diagnostics: _diagnostics,
        diagnosticsContext: diagnosticsContext,
      );

      final enabledFeatureFlagsFromSchema = _readEnabledFeatureFlags(
        bundle.document,
      );
      final enabledFeatureFlags = <String>{
        ...enabledFeatureFlagsFromConfig,
        ...enabledFeatureFlagsFromSchema,
      };

      return _LoadedScreen(
        bundle: bundle,
        source: source,
        errorMessage: errorMessage,
        schema: resolved.schema,
        refErrors: resolved.errors,
        configSnapshotId: configSnapshotId,
        enabledFeatureFlags: enabledFeatureFlags,
      );
    }

    if (effectiveSchemaBaseUrl.isNotEmpty) {
      final configFlags =
          configSnapshot?.enabledFeatureFlags ?? const <String>{};
      try {
        final result = await SchemaRuntime(
          loader: HttpSchemaLoader(
            baseUrl: effectiveSchemaBaseUrl,
            cache: httpCache,
            headersProvider: () => _buildCorrelationHeaders(
              configSnapshotId: bootstrap?.configSnapshotId,
            ),
          ),
          compatibilityChecker: compatibilityChecker,
          diagnostics: _diagnostics,
          diagnosticsContext: _diagnosticsContextForRequest(
            request,
            configSnapshotId: bootstrap?.configSnapshotId,
          ),
        ).load(request);

        if (!result.isSupported) {
          throw UnsupportedError(
            result.incompatibilityReason ?? 'Unsupported schema bundle',
          );
        }

        final bundle = result.bundle;
        return buildLoadedScreen(
          request,
          bundle,
          ScreenLoadSource.remote,
          configSnapshotId: bootstrap?.configSnapshotId,
          enabledFeatureFlagsFromConfig: configFlags,
        );
      } catch (error) {
        final bundledRequest = RuntimeScreenRequest(
          screenId: 'customer_home',
          product: bootstrap?.product ?? product,
        );
        request = bundledRequest;
        final bundle = await _loadBundledSchema(
          bundledRequest,
          compatibilityChecker,
        );
        return buildLoadedScreen(
          bundledRequest,
          bundle,
          ScreenLoadSource.fallback,
          errorMessage: error.toString(),
          configSnapshotId: bootstrap?.configSnapshotId,
          enabledFeatureFlagsFromConfig: configFlags,
        );
      }
    }

    final bundle = await _loadBundledSchema(request, compatibilityChecker);
    return buildLoadedScreen(request, bundle, ScreenLoadSource.bundled);
  }

  Future<SchemaBundle> _loadBundledSchema(
    RuntimeScreenRequest request,
    CustomerSchemaCompatibilityChecker compatibilityChecker,
  ) {
    return SchemaRuntime(
      loader: InMemorySchemaLoader(bundle: fallbackCustomerHomeBundle),
      compatibilityChecker: compatibilityChecker,
      diagnostics: _diagnostics,
      diagnosticsContext: _diagnosticsContextForRequest(request),
    ).load(request).then((r) {
      if (!r.isSupported) {
        throw StateError(
          'Bundled schema is incompatible: ${r.incompatibilityReason}',
        );
      }
      return r.bundle;
    });
  }

  Uri? _resolveTelemetryEndpoint({
    required ProductBootstrap? bootstrap,
    required String fallbackBaseUrl,
  }) {
    final raw = bootstrap?.telemetryIngestUrl;
    if (raw != null && raw.isNotEmpty) {
      return Uri.tryParse(raw);
    }
    if (fallbackBaseUrl.isEmpty) return null;
    final normalized = fallbackBaseUrl.endsWith('/')
        ? fallbackBaseUrl.substring(0, fallbackBaseUrl.length - 1)
        : fallbackBaseUrl;
    return Uri.tryParse('$normalized/telemetry/diagnostics');
  }

  DiagnosticsConfig _diagnosticsConfigFromSnapshot(ConfigSnapshot? snapshot) {
    int clampInt(int v, int min, int max) {
      if (v < min) return min;
      if (v > max) return max;
      return v;
    }

    final dedupeSeconds = snapshot?.dedupeTtlSeconds;
    final dedupeTtl = dedupeSeconds == null
        ? const Duration(seconds: 60)
        : Duration(seconds: clampInt(dedupeSeconds, 5, 600));

    final maxInfo = snapshot?.maxInfoPerSession;
    final maxWarn = snapshot?.maxWarnPerSession;

    return DiagnosticsConfig(
      enableDebug: kDebugMode,
      dedupeTtl: dedupeTtl,
      maxInfoPerSession: maxInfo == null ? 30 : clampInt(maxInfo, 0, 500),
      maxWarnPerSession: maxWarn == null ? 50 : clampInt(maxWarn, 0, 500),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LoadedScreen>(
      future: _screenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: resolveCustomerTheme(const <String, Object?>{}),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: resolveCustomerTheme(const <String, Object?>{}),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unable to load the customer schema.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }

        final loadedScreen = snapshot.data!;
        if (loadedScreen.schema == null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: resolveCustomerTheme(const <String, Object?>{}),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Schema parse failed:\n${loadedScreen.parseErrors.join('\n')}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }

        final screenSchema = loadedScreen.schema!;
        final enabledFeatureFlags = loadedScreen.enabledFeatureFlags;
        final diagnosticsContext = <String, Object?>{
          'app': <String, Object?>{
            'appId': 'customer-app',
            'buildFlavor': kDebugMode ? 'dev' : 'prod',
          },
          'schema': <String, Object?>{
            'bundleId': loadedScreen.bundle.schemaId,
            'bundleVersion': loadedScreen.bundle.schemaVersion,
            'screenId': screenSchema.id,
            if (screenSchema.service != null)
              'serviceSlug': screenSchema.service,
            'schemaFormatVersion': screenSchema.schemaVersion,
            'themeId': screenSchema.themeId,
            if (screenSchema.themeMode != null) 'mode': screenSchema.themeMode,
          },
          'flags': <String, Object?>{
            'featureFlags': enabledFeatureFlags.toList(growable: false),
          },
          if (loadedScreen.configSnapshotId != null)
            'config': <String, Object?>{
              'snapshotId': loadedScreen.configSnapshotId,
            },
        };

        final visibility = SchemaVisibilityContext(
          enabledFeatureFlags: enabledFeatureFlags,
          service: screenSchema.service,
          state: loadedScreen.bundle.document,
        );

        final actionDispatcher = TypeMapSchemaActionDispatcher(
          dispatchersByType: <String, SchemaActionDispatcher>{
            SchemaActionTypes.navigate: const NavigatorSchemaActionDispatcher(),
            SchemaActionTypes.openUrl: UrlSchemaActionDispatcher(
              openUrlHandler: const UrlLauncherOpenUrlHandler(),
              uriPolicy: const UriPolicy.allowAll(),
            ),
            SchemaActionTypes.submitForm: SubmitFormSchemaActionDispatcher(
              submitFormHandler: DiagnosticsSubmitFormHandler(
                diagnostics: _diagnostics,
                diagnosticsContext: diagnosticsContext,
              ),
            ),
            SchemaActionTypes.trackEvent: TrackEventSchemaActionDispatcher(
              trackEventHandler: DiagnosticsTrackEventHandler(
                diagnostics: _diagnostics,
                diagnosticsContext: diagnosticsContext,
              ),
            ),
          },
          fallback: const UnsupportedSchemaActionDispatcher(),
        );

        final renderer = SchemaRenderer(
          rootNode: screenSchema.root,
          registry: buildCustomerComponentRegistry(
            screen: screenSchema,
            actionDispatcher: actionDispatcher,
            visibility: visibility,
            diagnostics: _diagnostics,
            diagnosticsContext: diagnosticsContext,
          ),
        );

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: resolveCustomerTheme(loadedScreen.bundle.document),
          darkTheme: resolveCustomerTheme(
            loadedScreen.bundle.document,
            overrideMode: 'dark',
          ),
          themeMode: resolveThemeMode(loadedScreen.bundle.document),
          routes: {
            'schema.service': (context) =>
                _SchemaServiceScreen(baseUrl: widget.schemaBaseUrl),
          },
          home: Scaffold(
            appBar: AppBar(title: const Text('Daryeel2 Customer')),
            body: Column(
              children: [
                _SchemaStatusBanner(screen: loadedScreen),
                Expanded(
                  child: SchemaFormScope(
                    store: _formStore,
                    child: renderer.render(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SchemaServiceScreen extends StatelessWidget {
  const _SchemaServiceScreen({required this.baseUrl});

  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schema Service')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Base URL:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(baseUrl.isEmpty ? '<not configured>' : baseUrl),
            const SizedBox(height: 16),
            const Text(
              'This route is reached via a schema action of type "navigate".',
            ),
          ],
        ),
      ),
    );
  }
}

Set<String> _readEnabledFeatureFlags(Map<String, Object?> document) {
  final raw = document['featureFlags'];

  if (raw is List) {
    return raw.whereType<String>().where((f) => f.isNotEmpty).toSet();
  }

  if (raw is Map) {
    final out = <String>{};
    for (final entry in raw.entries) {
      if (entry.key is String && entry.value == true) {
        out.add(entry.key as String);
      }
    }
    return out;
  }

  return const <String>{};
}

class _SchemaStatusBanner extends StatelessWidget {
  const _SchemaStatusBanner({required this.screen});

  final _LoadedScreen screen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = switch (screen.source) {
      ScreenLoadSource.remote => colorScheme.secondaryContainer,
      ScreenLoadSource.bundled => colorScheme.surfaceContainerHighest,
      ScreenLoadSource.fallback => colorScheme.tertiaryContainer,
    };
    final textColor = switch (screen.source) {
      ScreenLoadSource.remote => colorScheme.onSecondaryContainer,
      ScreenLoadSource.bundled => colorScheme.onSurfaceVariant,
      ScreenLoadSource.fallback => colorScheme.onTertiaryContainer,
    };
    final message = switch (screen.source) {
      ScreenLoadSource.remote =>
        'Schema source: remote service (${screen.bundle.schemaId})',
      ScreenLoadSource.bundled =>
        'Schema source: bundled baseline (${screen.bundle.schemaId})',
      ScreenLoadSource.fallback =>
        'Schema source: bundled fallback (${screen.bundle.schemaId})',
    };

    return Container(
      width: double.infinity,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        screen.errorMessage == null
            ? message
            : '$message. Remote load failed: ${screen.errorMessage}',
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LoadedScreen {
  const _LoadedScreen({
    required this.bundle,
    required this.source,
    this.errorMessage,
    this.schema,
    this.parseErrors = const <SchemaParseError>[],
    this.refErrors = const <RefResolutionError>[],
    this.configSnapshotId,
    this.enabledFeatureFlags = const <String>{},
  });

  final SchemaBundle bundle;
  final ScreenLoadSource source;
  final String? errorMessage;
  final ScreenSchema? schema;
  final List<SchemaParseError> parseErrors;
  final List<RefResolutionError> refErrors;
  final String? configSnapshotId;
  final Set<String> enabledFeatureFlags;
}
