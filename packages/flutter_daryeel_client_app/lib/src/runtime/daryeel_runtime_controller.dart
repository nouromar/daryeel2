import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../actions/diagnostics_submit_form_handler.dart';
import '../actions/diagnostics_track_event_handler.dart';
import '../actions/url_launcher_open_url_handler.dart';
import '../cache/http_json_cache.dart';
import '../config/daryeel_client_config.dart';
import '../schema/bootstrap_loader.dart';
import '../schema/pinned_schema_store.dart';
import '../schema/pinned_theme_store.dart';
import '../schema/schema_loader.dart';
import '../schema/theme_loader.dart';
import 'daryeel_diagnostics_reporter.dart';
import 'daryeel_runtime_view_model.dart';

class DaryeelRuntimePolicy {
  const DaryeelRuntimePolicy({
    required this.compatibilityChecker,
    required this.actionPolicy,
    required this.enableRemoteThemes,
  });

  final SchemaCompatibilityChecker compatibilityChecker;
  final SchemaActionPolicy actionPolicy;
  final bool enableRemoteThemes;
}

class DaryeelRuntimeController {
  DaryeelRuntimeController({
    required this.config,
    required this.schemaBaseUrl,
    this.configBaseUrl,
    this.apiBaseUrl = '',
    this.requestHeadersProvider,
    this.httpClient,
    this.diagnosticsReporter,
    this.additionalDiagnosticsSinks = const <DiagnosticsSink>[],
    this.diagnosticsSinkOverride,
    this.openUrlHandlerOverride,
    this.submitFormHandlerOverride,
    this.trackEventHandlerOverride,
  });

  final DaryeelRuntimeConfig config;
  final String schemaBaseUrl;
  final String? configBaseUrl;
  final String apiBaseUrl;
  final RequestHeadersProvider? requestHeadersProvider;
  final http.Client? httpClient;
  final DaryeelDiagnosticsReporter? diagnosticsReporter;
  final List<DiagnosticsSink> additionalDiagnosticsSinks;
  final DiagnosticsSink? diagnosticsSinkOverride;
  final OpenUrlHandler? openUrlHandlerOverride;
  final SubmitFormHandler? submitFormHandlerOverride;
  final TrackEventHandler? trackEventHandlerOverride;

  Map<String, String> _buildEffectiveRequestHeaders(
    DaryeelDiagnosticsReporter reporter, {
    String? schemaVersion,
    String? configSnapshotId,
  }) {
    final correlation = reporter.buildCorrelationHeaders(
      schemaVersion: schemaVersion,
      configSnapshotId: configSnapshotId,
    );

    Map<String, String> extra;
    try {
      extra = requestHeadersProvider?.call() ?? const <String, String>{};
    } catch (_) {
      extra = const <String, String>{};
    }

    if (extra.isEmpty) return correlation;
    if (correlation.isEmpty) return extra;

    // Let the runtime keep control of correlation IDs.
    return <String, String>{...extra, ...correlation};
  }

  Future<DaryeelRuntimeViewModel> loadInitialScreen({
    String? screenIdOverride,
    String? serviceOverride,
  }) async {
    final product = config.product;
    final fallbackScreenId = config.fallbackBundle.schemaId;

    final totalStopwatch = Stopwatch()..start();
    int attemptCount = 0;
    int fallbackCount = 0;

    final reporter =
        diagnosticsReporter ??
        DaryeelDiagnosticsReporter(
          appId: config.appId,
          diagnosticsSinkOverride: diagnosticsSinkOverride,
          additionalSinks: additionalDiagnosticsSinks,
        );
    reporter.beginNewScreenLoad();

    final prefs = await SharedPreferences.getInstance();
    final client = httpClient ?? http.Client();

    // Created without diagnostics until we have a request + runtime diagnostics.
    var httpCache = HttpJsonCache(prefs: prefs, client: client);
    final pinnedStore = PinnedSchemaStore(prefs: prefs);
    final pinnedThemeStore = PinnedThemeStore(prefs: prefs);

    ProductBootstrap? bootstrap;
    ConfigSnapshot? configSnapshot;
    var effectiveSchemaBaseUrl = schemaBaseUrl;
    var effectiveThemeBaseUrl = schemaBaseUrl;
    var initialScreenId = fallbackScreenId;

    final bootstrapBaseUrl =
        (configBaseUrl != null && configBaseUrl!.isNotEmpty)
        ? configBaseUrl!
        : schemaBaseUrl;

    // Load last-known-good config snapshot first (fast/offline).
    final lkgJson = prefs.getString(config.effectiveLkgConfigSnapshotPrefsKey);
    if (lkgJson != null && lkgJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(lkgJson);
        if (decoded is Map) {
          configSnapshot = ConfigSnapshot.fromJson(
            Map<String, Object?>.from(decoded.cast<String, Object?>()),
          );
          if (configSnapshot.snapshotId.isNotEmpty) {
            reporter.activeConfigSnapshotId = configSnapshot.snapshotId;
          }
        }
      } catch (_) {
        // Ignore corrupt cache.
      }
    }

    if (bootstrapBaseUrl.isNotEmpty) {
      try {
        final loader = DaryeelBootstrapLoader(
          baseUrl: bootstrapBaseUrl,
          client: client,
          headersProvider: () => _buildEffectiveRequestHeaders(reporter),
          cache: httpCache,
        );

        bootstrap = await loader.loadBootstrap(product: product);
        if (bootstrap.configSnapshotId.isNotEmpty) {
          reporter.activeConfigSnapshotId = bootstrap.configSnapshotId;
        }

        effectiveSchemaBaseUrl =
            bootstrap.schemaServiceBaseUrl ?? schemaBaseUrl;
        effectiveThemeBaseUrl = bootstrap.themeServiceBaseUrl ?? schemaBaseUrl;
        if (bootstrap.initialScreenId.isNotEmpty) {
          initialScreenId = bootstrap.initialScreenId;
        }

        if (bootstrap.configSnapshotId.isNotEmpty) {
          final loadedSnapshot = await loader.loadSnapshot(
            snapshotId: bootstrap.configSnapshotId,
            configBaseUrl:
                (bootstrap.configServiceBaseUrl != null &&
                    bootstrap.configServiceBaseUrl!.isNotEmpty)
                ? bootstrap.configServiceBaseUrl
                : bootstrapBaseUrl,
          );
          configSnapshot = loadedSnapshot;
          await _writeLkgConfigSnapshot(prefs, loadedSnapshot);
        }
      } catch (_) {
        // Best-effort: fall back to bundled + cached config snapshot.
      }
    }

    final telemetryEndpoint = reporter.resolveTelemetryEndpoint(
      telemetryIngestUrl: bootstrap?.telemetryIngestUrl,
      fallbackBaseUrl: schemaBaseUrl,
    );

    final policy = DaryeelRuntimePolicy(
      compatibilityChecker: config.buildCompatibilityChecker(
        configSnapshot?.schemaCompatibilityPolicyOverlay,
      ),
      actionPolicy: config.buildActionPolicy(
        schemaBaseUrl: effectiveSchemaBaseUrl,
        apiBaseUrl: apiBaseUrl,
        configSnapshot: configSnapshot,
      ),
      enableRemoteThemes: configSnapshot?.enableRemoteThemes ?? false,
    );

    final diagnosticsConfig = reporter.diagnosticsConfigFromSnapshot(
      dedupeTtlSeconds: configSnapshot?.dedupeTtlSeconds,
      maxInfoPerSession: configSnapshot?.maxInfoPerSession,
      maxWarnPerSession: configSnapshot?.maxWarnPerSession,
    );

    final diagnostics = BudgetedRuntimeDiagnostics(
      sink: reporter.buildDiagnosticsSink(
        telemetryEndpoint: telemetryEndpoint,
        enableRemoteIngest: configSnapshot?.enableRemoteIngest ?? true,
      ),
      config: diagnosticsConfig,
    );

    final overrideId = screenIdOverride;
    if (overrideId != null && overrideId.isNotEmpty) {
      initialScreenId = overrideId;
    }

    var request = RuntimeScreenRequest(
      screenId: initialScreenId,
      product: (bootstrap?.product ?? '').isNotEmpty
          ? bootstrap!.product
          : product,
      service: serviceOverride,
    );

    // Now that the request + runtime diagnostics exist, re-create the cache so
    // it can emit cache-corruption diagnostics.
    httpCache = HttpJsonCache(
      prefs: prefs,
      client: client,
      diagnostics: diagnostics,
      diagnosticsContext: reporter.contextForRequest(request),
    );

    Future<LoadedScreen> buildLoadedScreen(
      RuntimeScreenRequest screenRequest,
      SchemaBundle bundle,
      ScreenLoadSource source, {
      String? errorMessage,
      String? configSnapshotId,
      Set<String> enabledFeatureFlagsFromConfig = const <String>{},
    }) async {
      final diagnosticsContext = reporter.contextForBundle(
        bundle,
        screenRequest,
        configSnapshotId,
      );

      final parsed = parseScreenSchemaWithDiagnostics(
        bundle.document,
        diagnostics: diagnostics,
        diagnosticsContext: diagnosticsContext,
      );
      final schema = parsed.value;
      if (schema == null) {
        final resolvedThemeIdRaw =
            bundle.document['themeId'] as String? ??
            bootstrap?.defaultThemeId ??
            config.defaultThemeId;
        final resolvedThemeModeRaw =
            bundle.document['themeMode'] as String? ??
            bootstrap?.defaultThemeMode ??
            config.defaultThemeMode ??
            'light';
        final resolvedThemeId =
            (resolvedThemeIdRaw != null && resolvedThemeIdRaw.isNotEmpty)
            ? resolvedThemeIdRaw
            : null;
        final resolvedThemeMode = resolvedThemeModeRaw.isNotEmpty
            ? resolvedThemeModeRaw
            : null;

        final localLightTheme = config.resolveLocalTheme(bundle.document);
        final localDarkTheme = config.resolveLocalTheme(
          bundle.document,
          overrideMode: 'dark',
        );
        final localThemeMode = config.resolveThemeMode(bundle.document);
        return LoadedScreen(
          bundle: bundle,
          source: source,
          bootstrapVersion: bootstrap?.bootstrapVersion,
          bootstrapProduct: bootstrap?.product,
          bootstrapConfigSnapshotId: bootstrap?.configSnapshotId,
          errorMessage: errorMessage,
          parseErrors: parsed.errors,
          configSnapshotId: configSnapshotId,
          theme: localLightTheme,
          darkTheme: localDarkTheme,
          themeMode: localThemeMode,
          resolvedThemeId: resolvedThemeId,
          resolvedThemeMode: resolvedThemeMode,
        );
      }

      final FragmentDocumentLoader fragmentLoader =
          source == ScreenLoadSource.remote
          ? HttpFragmentDocumentLoader(
              baseUrl: effectiveSchemaBaseUrl,
              client: client,
              cache: httpCache,
              headersProvider: () => _buildEffectiveRequestHeaders(
                reporter,
                schemaVersion: '${bundle.schemaId}@${bundle.schemaVersion}',
                configSnapshotId: configSnapshotId,
              ),
            )
          : InMemoryFragmentDocumentLoader(
              documents: config.fallbackFragmentDocuments,
            );

      final resolved = await resolveScreenRefsWithDiagnostics(
        schema: schema,
        loader: fragmentLoader,
        diagnostics: diagnostics,
        diagnosticsContext: diagnosticsContext,
      );

      // Theme fallback: always have a safe local theme.
      final localLightTheme = config.resolveLocalTheme(bundle.document);
      final localDarkTheme = config.resolveLocalTheme(
        bundle.document,
        overrideMode: 'dark',
      );
      final localThemeMode = config.resolveThemeMode(bundle.document);

      ThemeData lightTheme = localLightTheme;
      ThemeData darkTheme = localDarkTheme;
      ThemeMode themeMode = localThemeMode;
      String? themeDocId;
      bool usedRemoteTheme = false;
      ThemeLadderSource themeSource = ThemeLadderSource.local;

      final resolvedThemeIdRaw =
          bundle.document['themeId'] as String? ??
          bootstrap?.defaultThemeId ??
          config.defaultThemeId ??
          '';
      final resolvedThemeModeRaw =
          bundle.document['themeMode'] as String? ??
          bootstrap?.defaultThemeMode ??
          config.defaultThemeMode ??
          'light';
      final resolvedThemeId = resolvedThemeIdRaw.isNotEmpty
          ? resolvedThemeIdRaw
          : null;
      final resolvedThemeMode = resolvedThemeModeRaw.isNotEmpty
          ? resolvedThemeModeRaw
          : null;

      if (policy.enableRemoteThemes && source == ScreenLoadSource.remote) {
        final themeId = resolvedThemeIdRaw;
        final mode = resolvedThemeModeRaw;

        if (themeId.isNotEmpty && effectiveThemeBaseUrl.isNotEmpty) {
          try {
            final loader = DaryeelThemeLoader(
              baseUrl: effectiveThemeBaseUrl,
              product: screenRequest.product,
              pinnedStore: pinnedThemeStore,
              enablePinning: config.enableThemePinning,
              client: client,
              cache: httpCache,
              headersProvider: () => _buildEffectiveRequestHeaders(
                reporter,
                schemaVersion: '${bundle.schemaId}@${bundle.schemaVersion}',
                configSnapshotId: configSnapshotId,
              ),
            );

            final loadedTheme = await loader.loadTheme(
              themeId: themeId,
              themeMode: mode,
            );

            if (loadedTheme != null) {
              final mappedSource = switch (loadedTheme.source) {
                ThemeLoadSource.pinnedImmutable =>
                  ThemeLadderSource.pinnedImmutable,
                ThemeLoadSource.cachedPinned => ThemeLadderSource.cachedPinned,
                ThemeLoadSource.selector => ThemeLadderSource.selector,
              };

              themeSource = mappedSource;
              reporter.emitThemeSourceUsed(
                diagnostics,
                screenRequest,
                themeId: themeId,
                themeMode: mode,
                source: mappedSource,
                docId: loadedTheme.docId,
                configSnapshotId: configSnapshotId,
              );

              usedRemoteTheme = true;
              themeDocId = loadedTheme.docId;
              if (mode == 'dark') {
                darkTheme = loadedTheme.themeData;
              } else {
                lightTheme = loadedTheme.themeData;
              }
              themeMode = mode == 'dark' ? ThemeMode.dark : ThemeMode.light;
            } else {
              reporter.emitThemeFallbackToLocal(
                diagnostics,
                screenRequest,
                themeId: themeId,
                themeMode: mode,
                reason: ThemeLadderReason.remoteReturnedNull,
                configSnapshotId: configSnapshotId,
              );
            }
          } catch (error) {
            reporter.emitThemeFallbackToLocal(
              diagnostics,
              screenRequest,
              themeId: themeId,
              themeMode: mode,
              reason: ThemeLadderReason.exception,
              errorType: error.runtimeType.toString(),
              configSnapshotId: configSnapshotId,
            );
          }
        } else {
          reporter.emitThemeFallbackToLocal(
            diagnostics,
            screenRequest,
            themeId: themeId.isEmpty ? '<missing>' : themeId,
            themeMode: mode,
            reason: effectiveThemeBaseUrl.isEmpty
                ? ThemeLadderReason.noThemeBaseUrl
                : ThemeLadderReason.remoteReturnedNull,
            configSnapshotId: configSnapshotId,
          );
        }
      }

      final enabledFeatureFlagsFromSchema = _readEnabledFeatureFlags(
        bundle.document,
      );
      final enabledFeatureFlags = <String>{
        ...enabledFeatureFlagsFromConfig,
        ...enabledFeatureFlagsFromSchema,
      };

      return LoadedScreen(
        bundle: bundle,
        source: source,
        bootstrapVersion: bootstrap?.bootstrapVersion,
        bootstrapProduct: bootstrap?.product,
        bootstrapConfigSnapshotId: bootstrap?.configSnapshotId,
        errorMessage: errorMessage,
        schema: resolved.schema,
        parseErrors: parsed.errors,
        refErrors: resolved.errors,
        configSnapshotId: configSnapshotId,
        enabledFeatureFlags: enabledFeatureFlags,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        resolvedThemeId: resolvedThemeId,
        resolvedThemeMode: resolvedThemeMode,
        usedRemoteTheme: usedRemoteTheme,
        themeSource: themeSource,
        themeDocId: themeDocId,
      );
    }

    Future<LoadedScreen> finalize(
      LoadedScreen loaded, {
      required SchemaLadderSource finalSchemaSource,
      SchemaLadderReason? finalSchemaReason,
      String? configSnapshotId,
    }) async {
      totalStopwatch.stop();
      reporter.emitScreenLoadSummary(
        diagnostics,
        request,
        loaded.bundle,
        finalThemeSource: loaded.themeSource ?? ThemeLadderSource.local,
        themeDocId: loaded.themeDocId,
        usedRemoteTheme: loaded.usedRemoteTheme,
        parseErrorCount: loaded.parseErrors.length,
        refErrorCount: loaded.refErrors.length,
        finalSchemaSource: finalSchemaSource,
        finalSchemaReason: finalSchemaReason,
        schemaDocId: loaded.bundle.docId,
        attemptCount: attemptCount,
        fallbackCount: fallbackCount,
        totalLoadMs: totalStopwatch.elapsedMilliseconds,
        configSnapshotId: configSnapshotId,
      );
      return loaded.copyWith(
        schemaLadderSource: finalSchemaSource,
        schemaLadderReason: finalSchemaReason,
      );
    }

    if (effectiveSchemaBaseUrl.isNotEmpty) {
      final configFlags =
          configSnapshot?.enabledFeatureFlags ?? const <String>{};

      final pinnedDocId = config.enableSchemaPinning
          ? pinnedStore.readPinnedDocId(
              product: request.product,
              screenId: request.screenId,
            )
          : null;

      var allowCachedPinned = true;
      var pinnedImmutableHadException = false;

      Future<DaryeelRuntimeViewModel?> tryLoadCachedPinned(
        String pinnedDocId, {
        required SchemaLadderReason finalSchemaReason,
      }) async {
        attemptCount++;
        final cachedPinnedJson = httpCache.readCachedJson(
          'schema_screen_doc.$pinnedDocId',
        );
        if (cachedPinnedJson == null) {
          reporter.emitSchemaFallback(
            diagnostics,
            request,
            fromSource: SchemaLadderSource.cachedPinned,
            toSource: SchemaLadderSource.bundledFallback,
            reason: SchemaLadderReason.cachedPinnedMissing,
            configSnapshotId: bootstrap?.configSnapshotId,
          );
          fallbackCount++;
          return null;
        }

        try {
          final cachedPinnedBundle = SchemaBundle(
            schemaId: cachedPinnedJson['id'] as String? ?? request.screenId,
            schemaVersion:
                cachedPinnedJson['schemaVersion'] as String? ?? 'unknown',
            document: cachedPinnedJson,
            docId: pinnedDocId,
          );

          final loaded = await buildLoadedScreen(
            request,
            cachedPinnedBundle,
            ScreenLoadSource.remote,
            configSnapshotId: bootstrap?.configSnapshotId,
            enabledFeatureFlagsFromConfig: configFlags,
          );

          if (loaded.schema != null &&
              loaded.parseErrors.isEmpty &&
              loaded.refErrors.isEmpty) {
            reporter.emitSchemaSourceUsed(
              diagnostics,
              request,
              source: SchemaLadderSource.cachedPinned,
              docId: pinnedDocId,
              pinnedDocId: pinnedDocId,
              configSnapshotId: bootstrap?.configSnapshotId,
            );

            final finalized = await finalize(
              loaded,
              finalSchemaSource: SchemaLadderSource.cachedPinned,
              finalSchemaReason: finalSchemaReason,
              configSnapshotId: bootstrap?.configSnapshotId,
            );

            return _buildViewModel(
              diagnostics: diagnostics,
              policy: policy,
              request: request,
              screen: finalized,
            );
          }

          reporter.emitSchemaFallback(
            diagnostics,
            request,
            fromSource: SchemaLadderSource.cachedPinned,
            toSource: SchemaLadderSource.bundledFallback,
            reason: SchemaLadderReason.cachedPinnedInvalid,
            configSnapshotId: bootstrap?.configSnapshotId,
          );
          fallbackCount++;
          return null;
        } catch (error) {
          reporter.emitSchemaFallback(
            diagnostics,
            request,
            fromSource: SchemaLadderSource.cachedPinned,
            toSource: SchemaLadderSource.bundledFallback,
            reason: SchemaLadderReason.cachedPinnedException,
            errorType: error.runtimeType.toString(),
            configSnapshotId: bootstrap?.configSnapshotId,
          );
          fallbackCount++;
          return null;
        }
      }

      if (pinnedDocId != null) {
        attemptCount++;
        try {
          final pinnedResult = await SchemaRuntime(
            loader: HttpSchemaDocLoader(
              baseUrl: effectiveSchemaBaseUrl,
              docId: pinnedDocId,
              client: client,
              cache: httpCache,
              headersProvider: () => _buildEffectiveRequestHeaders(
                reporter,
                configSnapshotId: bootstrap?.configSnapshotId,
              ),
            ),
            compatibilityChecker: policy.compatibilityChecker,
            diagnostics: diagnostics,
            diagnosticsContext: reporter.contextForRequest(
              request,
              configSnapshotId: bootstrap?.configSnapshotId,
            ),
          ).load(request);

          if (pinnedResult.isSupported) {
            reporter.emitSchemaSourceUsed(
              diagnostics,
              request,
              source: SchemaLadderSource.pinnedImmutable,
              docId: pinnedDocId,
              pinnedDocId: pinnedDocId,
              configSnapshotId: bootstrap?.configSnapshotId,
            );

            final loaded = await buildLoadedScreen(
              request,
              pinnedResult.bundle,
              ScreenLoadSource.remote,
              configSnapshotId: bootstrap?.configSnapshotId,
              enabledFeatureFlagsFromConfig: configFlags,
            );

            final finalized = await finalize(
              loaded,
              finalSchemaSource: SchemaLadderSource.pinnedImmutable,
              configSnapshotId: bootstrap?.configSnapshotId,
            );

            return _buildViewModel(
              diagnostics: diagnostics,
              policy: policy,
              request: request,
              screen: finalized,
            );
          }

          reporter.emitSchemaPinCleared(
            diagnostics,
            request,
            pinnedDocId: pinnedDocId,
            reason: SchemaLadderReason.pinnedIncompatible,
            configSnapshotId: bootstrap?.configSnapshotId,
          );
          await pinnedStore.clearPinnedDocId(
            product: request.product,
            screenId: request.screenId,
          );

          reporter.emitSchemaFallback(
            diagnostics,
            request,
            fromSource: SchemaLadderSource.pinnedImmutable,
            toSource: SchemaLadderSource.selector,
            reason: SchemaLadderReason.pinnedIncompatible,
            configSnapshotId: bootstrap?.configSnapshotId,
          );
          fallbackCount++;

          allowCachedPinned = false;
        } catch (error) {
          reporter.emitSchemaFallback(
            diagnostics,
            request,
            fromSource: SchemaLadderSource.pinnedImmutable,
            toSource: SchemaLadderSource.selector,
            reason: SchemaLadderReason.pinnedException,
            errorType: error.runtimeType.toString(),
            configSnapshotId: bootstrap?.configSnapshotId,
          );
          fallbackCount++;

          pinnedImmutableHadException = true;
        }
      }

      try {
        attemptCount++;
        final result = await SchemaRuntime(
          loader: HttpSchemaLoader(
            baseUrl: effectiveSchemaBaseUrl,
            client: client,
            cache: httpCache,
            headersProvider: () => _buildEffectiveRequestHeaders(
              reporter,
              configSnapshotId: bootstrap?.configSnapshotId,
            ),
          ),
          compatibilityChecker: policy.compatibilityChecker,
          diagnostics: diagnostics,
          diagnosticsContext: reporter.contextForRequest(
            request,
            configSnapshotId: bootstrap?.configSnapshotId,
          ),
        ).load(request);

        if (!result.isSupported) {
          reporter.emitSchemaFallback(
            diagnostics,
            request,
            fromSource: SchemaLadderSource.selector,
            toSource: SchemaLadderSource.bundledFallback,
            reason: SchemaLadderReason.selectorIncompatible,
            configSnapshotId: bootstrap?.configSnapshotId,
          );
          fallbackCount++;

          final bundledRequest = RuntimeScreenRequest(
            screenId: fallbackScreenId,
            product: (bootstrap?.product ?? '').isNotEmpty
                ? bootstrap!.product
                : product,
          );
          request = bundledRequest;

          final bundle = await _loadBundledSchema(
            diagnostics: diagnostics,
            reporter: reporter,
            request: bundledRequest,
            compatibilityChecker: policy.compatibilityChecker,
          );

          reporter.emitSchemaSourceUsed(
            diagnostics,
            bundledRequest,
            source: SchemaLadderSource.bundledFallback,
            reason: SchemaLadderReason.selectorIncompatible,
            configSnapshotId: bootstrap?.configSnapshotId,
          );

          final loaded = await buildLoadedScreen(
            bundledRequest,
            bundle,
            ScreenLoadSource.fallback,
            errorMessage: result.incompatibilityReason,
            configSnapshotId: bootstrap?.configSnapshotId,
            enabledFeatureFlagsFromConfig: configFlags,
          );

          final finalized = await finalize(
            loaded,
            finalSchemaSource: SchemaLadderSource.bundledFallback,
            finalSchemaReason: SchemaLadderReason.selectorIncompatible,
            configSnapshotId: bootstrap?.configSnapshotId,
          );

          return _buildViewModel(
            diagnostics: diagnostics,
            policy: policy,
            request: bundledRequest,
            screen: finalized,
          );
        }

        final bundle = result.bundle;
        final loaded = await buildLoadedScreen(
          request,
          bundle,
          ScreenLoadSource.remote,
          configSnapshotId: bootstrap?.configSnapshotId,
          enabledFeatureFlagsFromConfig: configFlags,
        );

        reporter.emitSchemaSourceUsed(
          diagnostics,
          request,
          source: SchemaLadderSource.selector,
          docId: bundle.docId,
          configSnapshotId: bootstrap?.configSnapshotId,
        );

        if (config.enableSchemaPinning &&
            loaded.schema != null &&
            loaded.parseErrors.isEmpty &&
            loaded.refErrors.isEmpty &&
            bundle.docId != null &&
            bundle.docId!.isNotEmpty) {
          await pinnedStore.writePinnedDocId(
            product: request.product,
            screenId: request.screenId,
            docId: bundle.docId!,
          );

          reporter.emitSchemaPinPromoted(
            diagnostics,
            request,
            docId: bundle.docId!,
            configSnapshotId: bootstrap?.configSnapshotId,
          );

          await httpCache.write(
            cacheKey: 'schema_screen_doc.${bundle.docId!}',
            json: bundle.document,
            etag: null,
          );
        }

        final finalized = await finalize(
          loaded,
          finalSchemaSource: SchemaLadderSource.selector,
          configSnapshotId: bootstrap?.configSnapshotId,
        );

        return _buildViewModel(
          diagnostics: diagnostics,
          policy: policy,
          request: request,
          screen: finalized,
        );
      } catch (error) {
        if (pinnedDocId != null &&
            allowCachedPinned &&
            pinnedImmutableHadException) {
          reporter.emitSchemaFallback(
            diagnostics,
            request,
            fromSource: SchemaLadderSource.selector,
            toSource: SchemaLadderSource.cachedPinned,
            reason: SchemaLadderReason.selectorException,
            errorType: error.runtimeType.toString(),
            configSnapshotId: bootstrap?.configSnapshotId,
          );
          fallbackCount++;

          final cachedPinnedVm = await tryLoadCachedPinned(
            pinnedDocId,
            finalSchemaReason: SchemaLadderReason.selectorException,
          );
          if (cachedPinnedVm != null) {
            return cachedPinnedVm;
          }
        }

        reporter.emitSchemaFallback(
          diagnostics,
          request,
          fromSource: SchemaLadderSource.selector,
          toSource: SchemaLadderSource.bundledFallback,
          reason: SchemaLadderReason.selectorException,
          errorType: error.runtimeType.toString(),
          configSnapshotId: bootstrap?.configSnapshotId,
        );
        fallbackCount++;

        final bundledRequest = RuntimeScreenRequest(
          screenId: fallbackScreenId,
          product: (bootstrap?.product ?? '').isNotEmpty
              ? bootstrap!.product
              : product,
        );
        request = bundledRequest;

        final bundle = await _loadBundledSchema(
          diagnostics: diagnostics,
          reporter: reporter,
          request: bundledRequest,
          compatibilityChecker: policy.compatibilityChecker,
        );

        reporter.emitSchemaSourceUsed(
          diagnostics,
          bundledRequest,
          source: SchemaLadderSource.bundledFallback,
          reason: SchemaLadderReason.selectorException,
          configSnapshotId: bootstrap?.configSnapshotId,
        );

        final loaded = await buildLoadedScreen(
          bundledRequest,
          bundle,
          ScreenLoadSource.fallback,
          errorMessage: error.toString(),
          configSnapshotId: bootstrap?.configSnapshotId,
          enabledFeatureFlagsFromConfig: configFlags,
        );

        final finalized = await finalize(
          loaded,
          finalSchemaSource: SchemaLadderSource.bundledFallback,
          finalSchemaReason: SchemaLadderReason.selectorException,
          configSnapshotId: bootstrap?.configSnapshotId,
        );

        return _buildViewModel(
          diagnostics: diagnostics,
          policy: policy,
          request: bundledRequest,
          screen: finalized,
        );
      }
    }

    final bundle = await _loadBundledSchema(
      diagnostics: diagnostics,
      reporter: reporter,
      request: request,
      compatibilityChecker: policy.compatibilityChecker,
    );

    reporter.emitSchemaSourceUsed(
      diagnostics,
      request,
      source: SchemaLadderSource.bundled,
      reason: effectiveSchemaBaseUrl.isEmpty
          ? SchemaLadderReason.noRemoteBaseUrl
          : null,
    );

    final loaded = await buildLoadedScreen(
      request,
      bundle,
      ScreenLoadSource.bundled,
    );

    final finalized = await finalize(
      loaded,
      finalSchemaSource: SchemaLadderSource.bundled,
      finalSchemaReason: effectiveSchemaBaseUrl.isEmpty
          ? SchemaLadderReason.noRemoteBaseUrl
          : null,
    );

    return _buildViewModel(
      diagnostics: diagnostics,
      policy: policy,
      request: request,
      screen: finalized,
    );
  }

  DaryeelRuntimeViewModel _buildViewModel({
    required RuntimeDiagnostics diagnostics,
    required DaryeelRuntimePolicy policy,
    required RuntimeScreenRequest request,
    required LoadedScreen screen,
  }) {
    final schema = screen.schema;
    final enabledFeatureFlags = screen.enabledFeatureFlags;

    final visibility = SchemaVisibilityContext(
      enabledFeatureFlags: enabledFeatureFlags,
      service: schema?.service,
      state: screen.bundle.document,
    );

    final diagnosticsContext = <String, Object?>{
      'app': <String, Object?>{
        'appId': config.appId,
        'buildFlavor': kDebugMode ? 'dev' : 'prod',
      },
      'schema': <String, Object?>{
        'bundleId': screen.bundle.schemaId,
        'bundleVersion': screen.bundle.schemaVersion,
        'screenId': schema?.id ?? request.screenId,
        if (schema?.service != null) 'serviceSlug': schema!.service,
        'schemaFormatVersion': schema?.schemaVersion,
        'themeId': schema?.themeId,
        if (schema?.themeMode != null) 'mode': schema!.themeMode,
      },
      'flags': <String, Object?>{
        'featureFlags': enabledFeatureFlags.toList(growable: false),
      },
      if (screen.configSnapshotId != null)
        'config': <String, Object?>{'snapshotId': screen.configSnapshotId},
    };

    return DaryeelRuntimeViewModel(
      screen: screen,
      diagnostics: diagnostics,
      actionDispatcher: TypeMapSchemaActionDispatcher(
        dispatchersByType: <String, SchemaActionDispatcher>{
          SchemaActionTypes.navigate: const NavigatorSchemaActionDispatcher(),
          SchemaActionTypes.setState: const NavigatorSchemaActionDispatcher(),
          SchemaActionTypes.openUrl: UrlSchemaActionDispatcher(
            openUrlHandler:
                openUrlHandlerOverride ?? const UrlLauncherOpenUrlHandler(),
            uriPolicy: policy.actionPolicy.openUrlPolicy,
          ),
          SchemaActionTypes.submitForm: SubmitFormSchemaActionDispatcher(
            submitFormHandler:
                submitFormHandlerOverride ??
                DiagnosticsSubmitFormHandler(
                  diagnostics: diagnostics,
                  diagnosticsContext: diagnosticsContext,
                ),
          ),
          SchemaActionTypes.trackEvent: TrackEventSchemaActionDispatcher(
            trackEventHandler:
                trackEventHandlerOverride ??
                DiagnosticsTrackEventHandler(
                  diagnostics: diagnostics,
                  diagnosticsContext: diagnosticsContext,
                ),
          ),
        },
        // If an action type is allowlisted but has no dispatcher yet, we
        // deliberately throw UnsupportedError here so the runtime can
        // convert it into a no-op with diagnostics.
        fallback: const UnsupportedSchemaActionDispatcher(),
      ),
      actionPolicy: policy.actionPolicy,
      visibility: visibility,
      rendererDiagnosticsContext: diagnosticsContext,
    );
  }

  Future<SchemaBundle> _loadBundledSchema({
    required RuntimeDiagnostics diagnostics,
    required DaryeelDiagnosticsReporter reporter,
    required RuntimeScreenRequest request,
    required SchemaCompatibilityChecker compatibilityChecker,
  }) async {
    final result = await SchemaRuntime(
      loader: InMemorySchemaLoader(bundle: config.fallbackBundle),
      compatibilityChecker: compatibilityChecker,
      diagnostics: diagnostics,
      diagnosticsContext: reporter.contextForRequest(request),
    ).load(request);

    if (!result.isSupported) {
      throw StateError(
        'Bundled schema is incompatible: ${result.incompatibilityReason}',
      );
    }

    return result.bundle;
  }

  static Set<String> _readEnabledFeatureFlags(Map<String, Object?> document) {
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

  Future<void> _writeLkgConfigSnapshot(
    SharedPreferences prefs,
    ConfigSnapshot snapshot,
  ) async {
    try {
      await prefs.setString(
        config.effectiveLkgConfigSnapshotPrefsKey,
        jsonEncode(snapshot.toJson()),
      );
    } catch (_) {
      // Best-effort cache.
    }
  }
}
