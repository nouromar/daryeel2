import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../cache/http_json_cache.dart';
import '../actions/diagnostics_submit_form_handler.dart';
import '../actions/diagnostics_track_event_handler.dart';
import '../actions/url_launcher_open_url_handler.dart';
import '../schema/customer_bootstrap_loader.dart';
import '../schema/customer_schema_loader.dart';
import '../schema/customer_theme_loader.dart';
import '../schema/fallback_fragment_documents.dart';
import '../schema/fallback_schema_bundle.dart';
import '../schema/pinned_schema_store.dart';
import '../schema/pinned_theme_store.dart';
import '../ui/customer_theme.dart';
import 'customer_diagnostics_reporter.dart';
import 'customer_runtime_policy_provider.dart';
import 'customer_runtime_view_model.dart';

class CustomerRuntimeController {
  CustomerRuntimeController({
    required this.schemaBaseUrl,
    this.httpClient,
    this.diagnosticsSinkOverride,
    this.openUrlHandlerOverride,
    this.submitFormHandlerOverride,
    this.trackEventHandlerOverride,
  });

  final String schemaBaseUrl;
  final http.Client? httpClient;
  final DiagnosticsSink? diagnosticsSinkOverride;
  final OpenUrlHandler? openUrlHandlerOverride;
  final SubmitFormHandler? submitFormHandlerOverride;
  final TrackEventHandler? trackEventHandlerOverride;

  static const String _prefsLkgConfigSnapshotJsonKey =
      'customer_app.lkg_config_snapshot_json';

  Future<CustomerRuntimeViewModel> loadInitialScreen() async {
    const product = 'customer_app';

    final totalStopwatch = Stopwatch()..start();
    int attemptCount = 0;
    int fallbackCount = 0;

    final reporter = CustomerDiagnosticsReporter(
      diagnosticsSinkOverride: diagnosticsSinkOverride,
    );

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
    var initialScreenId = 'customer_home';

    // Load last-known-good config snapshot first (fast/offline).
    final lkgJson = prefs.getString(_prefsLkgConfigSnapshotJsonKey);
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

    if (schemaBaseUrl.isNotEmpty) {
      try {
        final loader = CustomerBootstrapLoader(
          baseUrl: schemaBaseUrl,
          client: client,
          headersProvider: () => reporter.buildCorrelationHeaders(),
          cache: httpCache,
        );

        bootstrap = await loader.loadBootstrap(product: product);
        if (bootstrap.configSnapshotId.isNotEmpty) {
          reporter.activeConfigSnapshotId = bootstrap.configSnapshotId;
        }

        effectiveSchemaBaseUrl =
            bootstrap.schemaServiceBaseUrl ?? schemaBaseUrl;
        effectiveThemeBaseUrl = bootstrap.themeServiceBaseUrl ?? schemaBaseUrl;
        initialScreenId = bootstrap.initialScreenId;

        if (bootstrap.configSnapshotId.isNotEmpty) {
          final loadedSnapshot = await loader.loadSnapshot(
            snapshotId: bootstrap.configSnapshotId,
            configBaseUrl: bootstrap.configServiceBaseUrl,
          );
          configSnapshot = loadedSnapshot;
          await _writeLkgConfigSnapshot(prefs, loadedSnapshot);
        }
      } catch (_) {
        // Best-effort: fall back to hardcoded bootstrap.
      }
    }

    final telemetryEndpoint = reporter.resolveTelemetryEndpoint(
      telemetryIngestUrl: bootstrap?.telemetryIngestUrl,
      fallbackBaseUrl: schemaBaseUrl,
    );

    // Policies (compatibility + actions + rollout flags)
    final policy = const CustomerRuntimePolicyProvider().build(
      schemaBaseUrl: schemaBaseUrl,
      configSnapshot: configSnapshot,
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

    var request = RuntimeScreenRequest(
      screenId: initialScreenId,
      product: bootstrap?.product ?? product,
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
        final localLightTheme = resolveCustomerTheme(bundle.document);
        final localDarkTheme = resolveCustomerTheme(
          bundle.document,
          overrideMode: 'dark',
        );
        final localThemeMode = resolveThemeMode(bundle.document);
        return LoadedScreen(
          bundle: bundle,
          source: source,
          errorMessage: errorMessage,
          parseErrors: parsed.errors,
          theme: localLightTheme,
          darkTheme: localDarkTheme,
          themeMode: localThemeMode,
        );
      }

      final FragmentDocumentLoader fragmentLoader =
          source == ScreenLoadSource.remote
          ? HttpFragmentDocumentLoader(
              baseUrl: effectiveSchemaBaseUrl,
              client: client,
              cache: httpCache,
              headersProvider: () => reporter.buildCorrelationHeaders(
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
        diagnostics: diagnostics,
        diagnosticsContext: diagnosticsContext,
      );

      // Theme fallback: always have a safe local theme.
      final localLightTheme = resolveCustomerTheme(bundle.document);
      final localDarkTheme = resolveCustomerTheme(
        bundle.document,
        overrideMode: 'dark',
      );
      final localThemeMode = resolveThemeMode(bundle.document);

      ThemeData lightTheme = localLightTheme;
      ThemeData darkTheme = localDarkTheme;
      ThemeMode themeMode = localThemeMode;
      String? themeDocId;
      bool usedRemoteTheme = false;
      ThemeLadderSource themeSource = ThemeLadderSource.local;

      if (policy.enableRemoteThemes && source == ScreenLoadSource.remote) {
        final themeId =
            bundle.document['themeId'] as String? ?? 'customer-default';
        final mode =
            bundle.document['themeMode'] as String? ??
            bootstrap?.defaultThemeMode ??
            'light';

        if (effectiveThemeBaseUrl.isNotEmpty) {
          try {
            final loader = CustomerThemeLoader(
              baseUrl: effectiveThemeBaseUrl,
              product: screenRequest.product,
              pinnedStore: pinnedThemeStore,
              client: client,
              cache: httpCache,
              headersProvider: () => reporter.buildCorrelationHeaders(
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
            themeId: themeId,
            themeMode: mode,
            reason: ThemeLadderReason.noThemeBaseUrl,
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
        errorMessage: errorMessage,
        schema: resolved.schema,
        parseErrors: parsed.errors,
        refErrors: resolved.errors,
        configSnapshotId: configSnapshotId,
        enabledFeatureFlags: enabledFeatureFlags,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
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
      return loaded;
    }

    if (effectiveSchemaBaseUrl.isNotEmpty) {
      final configFlags =
          configSnapshot?.enabledFeatureFlags ?? const <String>{};

      // Fallback ladder:
      // 1) pinned immutable doc (network)
      // 2) cached pinned doc (LKG)
      // 3) selector (latest)
      // 4) bundled
      final pinnedDocId = pinnedStore.readPinnedDocId(
        product: request.product,
        screenId: request.screenId,
      );

      var allowCachedPinned = true;

      if (pinnedDocId != null) {
        attemptCount++;
        try {
          final pinnedResult = await SchemaRuntime(
            loader: HttpSchemaDocLoader(
              baseUrl: effectiveSchemaBaseUrl,
              docId: pinnedDocId,
              client: client,
              cache: httpCache,
              headersProvider: () => reporter.buildCorrelationHeaders(
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
            toSource: SchemaLadderSource.cachedPinned,
            reason: SchemaLadderReason.pinnedException,
            errorType: error.runtimeType.toString(),
            configSnapshotId: bootstrap?.configSnapshotId,
          );
          fallbackCount++;
        }

        if (allowCachedPinned) {
          attemptCount++;
          final cachedPinnedJson = httpCache.readCachedJson(
            'schema_screen_doc.$pinnedDocId',
          );
          if (cachedPinnedJson != null) {
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
                toSource: SchemaLadderSource.selector,
                reason: SchemaLadderReason.cachedPinnedInvalid,
                configSnapshotId: bootstrap?.configSnapshotId,
              );
              fallbackCount++;
            } catch (error) {
              reporter.emitSchemaFallback(
                diagnostics,
                request,
                fromSource: SchemaLadderSource.cachedPinned,
                toSource: SchemaLadderSource.selector,
                reason: SchemaLadderReason.cachedPinnedException,
                errorType: error.runtimeType.toString(),
                configSnapshotId: bootstrap?.configSnapshotId,
              );
              fallbackCount++;
            }
          } else {
            reporter.emitSchemaFallback(
              diagnostics,
              request,
              fromSource: SchemaLadderSource.cachedPinned,
              toSource: SchemaLadderSource.selector,
              reason: SchemaLadderReason.cachedPinnedMissing,
              configSnapshotId: bootstrap?.configSnapshotId,
            );
            fallbackCount++;
          }
        }
      }

      try {
        attemptCount++;
        final result = await SchemaRuntime(
          loader: HttpSchemaLoader(
            baseUrl: effectiveSchemaBaseUrl,
            client: client,
            cache: httpCache,
            headersProvider: () => reporter.buildCorrelationHeaders(
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
            screenId: 'customer_home',
            product: bootstrap?.product ?? product,
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

        if (loaded.schema != null &&
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
          screenId: 'customer_home',
          product: bootstrap?.product ?? product,
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

  CustomerRuntimeViewModel _buildViewModel({
    required RuntimeDiagnostics diagnostics,
    required CustomerRuntimePolicy policy,
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
        'appId': 'customer-app',
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

    return CustomerRuntimeViewModel(
      screen: screen,
      diagnostics: diagnostics,
      actionDispatcher: TypeMapSchemaActionDispatcher(
        dispatchersByType: <String, SchemaActionDispatcher>{
          SchemaActionTypes.navigate: const NavigatorSchemaActionDispatcher(),
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
        // convert it into a no-op with diagnostics (instead of incorrectly
        // reporting it as executed).
        fallback: const UnsupportedSchemaActionDispatcher(),
      ),
      actionPolicy: policy.actionPolicy,
      visibility: visibility,
      rendererDiagnosticsContext: diagnosticsContext,
    );
  }

  Future<SchemaBundle> _loadBundledSchema({
    required RuntimeDiagnostics diagnostics,
    required CustomerDiagnosticsReporter reporter,
    required RuntimeScreenRequest request,
    required SchemaCompatibilityChecker compatibilityChecker,
  }) async {
    final result = await SchemaRuntime(
      loader: InMemorySchemaLoader(bundle: fallbackCustomerHomeBundle),
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

  static Future<void> _writeLkgConfigSnapshot(
    SharedPreferences prefs,
    ConfigSnapshot snapshot,
  ) async {
    try {
      await prefs.setString(
        _prefsLkgConfigSnapshotJsonKey,
        jsonEncode(snapshot.toJson()),
      );
    } catch (_) {
      // Best-effort cache.
    }
  }
}
