import 'dart:convert';

import 'package:customer_app/src/runtime/customer_runtime_controller.dart';
import 'package:customer_app/src/runtime/customer_runtime_view_model.dart';
import 'package:customer_app/src/schema/pinned_schema_store.dart';
import 'package:customer_app/src/schema/pinned_theme_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scenario_matrix.dart';
import 'support/scenario_server.dart';

class _NoopOpenUrlHandler extends OpenUrlHandler {
  const _NoopOpenUrlHandler();

  @override
  Future<void> openUrl(Uri uri) async {}
}

class _NoopSubmitFormHandler extends SubmitFormHandler {
  const _NoopSubmitFormHandler();

  @override
  Future<SubmitFormResponse> submit(
    BuildContext context,
    SubmitFormRequest request,
  ) async {
    return const SubmitFormResponse(ok: true);
  }
}

class _NoopTrackEventHandler extends TrackEventHandler {
  const _NoopTrackEventHandler();

  @override
  Future<void> trackEvent(
    String eventName, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {}
}

Map<String, Object?> _bootstrap({
  required String baseUrl,
  String product = 'customer_app',
  String initialScreenId = 'customer_home',
  String snapshotId = 'snap-1',
}) {
  return <String, Object?>{
    'bootstrapVersion': 1,
    'product': product,
    'initialScreenId': initialScreenId,
    'defaultThemeId': 'customer-default',
    'defaultThemeMode': 'light',
    'configSchemaVersion': 1,
    'configSnapshotId': snapshotId,
    'configTtlSeconds': 3600,
    'schemaServiceBaseUrl': baseUrl,
    'themeServiceBaseUrl': baseUrl,
    'configServiceBaseUrl': baseUrl,
    'telemetryIngestUrl': '',
  };
}

Map<String, Object?> _configSnapshot({
  String snapshotId = 'snap-1',
  bool enableRemoteThemes = false,
  Map<String, Object?> runtime = const <String, Object?>{},
  List<String> featureFlags = const <String>[],
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'snapshotId': snapshotId,
    'flags': <String, Object?>{'featureFlags': featureFlags},
    'telemetry': const <String, Object?>{
      'enableRemoteIngest': false,
      'dedupeTtlSeconds': 5,
      'maxInfoPerSession': 200,
      'maxWarnPerSession': 200,
    },
    'runtime': <String, Object?>{
      'enableRemoteThemes': enableRemoteThemes,
      ...runtime,
    },
    'serviceCatalog': const <String, Object?>{},
  };
}

Map<String, Object?> _screenDoc({
  required String id,
  String schemaVersion = '1.0',
  String product = 'customer_app',
  String themeId = 'customer-default',
  String themeMode = 'light',
  List<Object?> body = const <Object?>[],
  Map<String, Object?> actions = const <String, Object?>{},
  Object? featureFlags,
  Map<String, Object?>? meta,
}) {
  return <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'documentType': 'screen',
    'product': product,
    'themeId': themeId,
    'themeMode': themeMode,
    if (meta != null) 'meta': meta,
    if (featureFlags != null) 'featureFlags': featureFlags,
    'root': <String, Object?>{
      'type': 'ScreenTemplate',
      'slots': <String, Object?>{'body': body},
    },
    'actions': actions,
  };
}

Map<String, Object?> _fragmentDoc({
  required String id,
  required Map<String, Object?> node,
}) {
  return <String, Object?>{
    'schemaVersion': '1.0',
    'id': id,
    'documentType': 'fragment',
    'node': node,
  };
}

Map<String, Object?> _themeDoc({
  required String themeId,
  required String themeMode,
  Map<String, Object?> tokens = const <String, Object?>{},
}) {
  return <String, Object?>{
    'themeId': themeId,
    'themeMode': themeMode,
    'inherits': const <Object?>[],
    'tokens': tokens,
  };
}

DiagnosticEvent? _firstEvent(InMemoryDiagnosticsSink sink, String eventName) {
  for (final e in sink.events) {
    if (e.eventName == eventName) return e;
  }
  return null;
}

List<DiagnosticEvent> _events(InMemoryDiagnosticsSink sink, String eventName) {
  return sink.events.where((e) => e.eventName == eventName).toList();
}

Future<CustomerRuntimeController> _buildController(
  ScenarioServer server,
  InMemoryDiagnosticsSink sink,
) async {
  return CustomerRuntimeController(
    schemaBaseUrl: server.baseUrl,
    httpClient: server.client,
    diagnosticsSinkOverride: sink,
    openUrlHandlerOverride: const _NoopOpenUrlHandler(),
    submitFormHandlerOverride: const _NoopSubmitFormHandler(),
    trackEventHandlerOverride: const _NoopTrackEventHandler(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scenarios = <ScenarioCase>[
    ScenarioCase(
      name: 'selector success promotes pin + emits diagnostics',
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(snapshotId: 'snap-1', json: _configSnapshot());
        server.stubScreen(
          screenId: 'customer_home',
          doc: ScenarioJsonDoc(
            json: _screenDoc(
              id: 'customer_home',
              body: const <Object?>[
                {
                  'type': 'InfoCard',
                  'props': {'title': 'Remote home'},
                },
              ],
            ),
            etag: 'E1',
            headers: const <String, String>{'x-daryeel-doc-id': 'doc-1'},
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();

        expect(vm.screen.source, ScreenLoadSource.remote);
        expect(vm.screen.bundle.docId, 'doc-1');

        final sourceUsed = _firstEvent(
          run.sink,
          SchemaLadderEventNames.sourceUsed,
        );
        expect(sourceUsed, isNotNull);
        expect(
          sourceUsed!.payload['source'],
          SchemaLadderSource.selector.wireValue,
        );
        expect(sourceUsed.payload['docId'], 'doc-1');

        final pinPromoted = _firstEvent(
          run.sink,
          SchemaLadderEventNames.pinPromoted,
        );
        expect(pinPromoted, isNotNull);
        expect(pinPromoted!.payload['docId'], 'doc-1');

        expect(
          run.prefs.getString(
            PinnedSchemaStore.keyFor(
              product: 'customer_app',
              screenId: 'customer_home',
            ),
          ),
          'doc-1',
        );
      },
    ),
    ScenarioCase(
      name: 'pinned immutable doc is used before selector',
      initialPrefs: <String, Object>{
        PinnedSchemaStore.keyFor(
          product: 'customer_app',
          screenId: 'customer_home',
        ): 'doc-1',
      },
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(snapshotId: 'snap-1', json: _configSnapshot());

        server.stubScreenDoc(
          docId: 'doc-1',
          doc: ScenarioJsonDoc(
            json: _screenDoc(
              id: 'customer_home',
              body: const <Object?>[
                {
                  'type': 'InfoCard',
                  'props': {'title': 'Pinned home'},
                },
              ],
            ),
          ),
        );

        server.stubScreen(
          screenId: 'customer_home',
          doc: ScenarioJsonDoc(
            json: _screenDoc(id: 'customer_home'),
            headers: const <String, String>{'x-daryeel-doc-id': 'doc-selector'},
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();
        expect(vm.screen.bundle.docId, 'doc-1');

        final sourceUsed = _firstEvent(
          run.sink,
          SchemaLadderEventNames.sourceUsed,
        );
        expect(sourceUsed, isNotNull);
        expect(
          sourceUsed!.payload['source'],
          SchemaLadderSource.pinnedImmutable.wireValue,
        );
        expect(sourceUsed.payload['docId'], 'doc-1');

        final selectorHits = run.server.requests.where(
          (r) => r.path == '/schemas/screens/customer_home',
        );
        expect(selectorHits, isEmpty);
      },
    ),
    ScenarioCase(
      name: 'pinned incompatible clears pin and falls back to selector',
      initialPrefs: <String, Object>{
        PinnedSchemaStore.keyFor(
          product: 'customer_app',
          screenId: 'customer_home',
        ): 'doc-bad',
      },
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(snapshotId: 'snap-1', json: _configSnapshot());

        server.stubScreenDoc(
          docId: 'doc-bad',
          doc: ScenarioJsonDoc(
            json: _screenDoc(id: 'customer_home', schemaVersion: '9.9'),
          ),
        );

        server.stubScreen(
          screenId: 'customer_home',
          doc: ScenarioJsonDoc(
            json: _screenDoc(id: 'customer_home'),
            headers: const <String, String>{'x-daryeel-doc-id': 'doc-good'},
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();
        expect(vm.screen.bundle.docId, 'doc-good');

        final pinCleared = _firstEvent(
          run.sink,
          SchemaLadderEventNames.pinCleared,
        );
        expect(pinCleared, isNotNull);
        expect(pinCleared!.payload['pinnedDocId'], 'doc-bad');
        expect(
          pinCleared.payload['reasonCode'],
          SchemaLadderReason.pinnedIncompatible.wireValue,
        );

        expect(
          run.prefs.getString(
            PinnedSchemaStore.keyFor(
              product: 'customer_app',
              screenId: 'customer_home',
            ),
          ),
          'doc-good',
        );
      },
    ),
    ScenarioCase(
      name: 'pinned network failure falls back to cached pinned doc',
      initialPrefs: () {
        final cachedDoc = _screenDoc(
          id: 'customer_home',
          body: const <Object?>[
            {
              'type': 'InfoCard',
              'props': {'title': 'Cached pinned home'},
            },
          ],
        );

        return <String, Object>{
          PinnedSchemaStore.keyFor(
            product: 'customer_app',
            screenId: 'customer_home',
          ): 'doc-3',
          'http_cache.schema_screen_doc.doc-3.body_json': jsonEncode(cachedDoc),
        };
      }(),
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(snapshotId: 'snap-1', json: _configSnapshot());

        server.stubScreenDoc(
          docId: 'doc-3',
          doc: const ScenarioJsonDoc(
            json: <String, Object?>{},
            abortConnection: true,
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();
        expect(vm.screen.bundle.docId, 'doc-3');

        final sourceUsed = _firstEvent(
          run.sink,
          SchemaLadderEventNames.sourceUsed,
        );
        expect(sourceUsed, isNotNull);
        expect(
          sourceUsed!.payload['source'],
          SchemaLadderSource.cachedPinned.wireValue,
        );
        expect(sourceUsed.payload['docId'], 'doc-3');

        final fallback = _firstEvent(run.sink, SchemaLadderEventNames.fallback);
        expect(fallback, isNotNull);
        expect(
          fallback!.payload['reasonCode'],
          SchemaLadderReason.pinnedException.wireValue,
        );
      },
    ),
    ScenarioCase(
      name: 'selector incompatible falls back to bundled fallback',
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(snapshotId: 'snap-1', json: _configSnapshot());

        server.stubScreen(
          screenId: 'customer_home',
          doc: ScenarioJsonDoc(
            json: _screenDoc(id: 'customer_home', schemaVersion: '999.0'),
            headers: const <String, String>{'x-daryeel-doc-id': 'doc-bad'},
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();

        expect(vm.screen.source, ScreenLoadSource.fallback);
        expect(vm.screen.errorMessage, contains('Unsupported schema version'));

        final sourceUsedEvents = _events(
          run.sink,
          SchemaLadderEventNames.sourceUsed,
        );
        expect(
          sourceUsedEvents.any(
            (e) =>
                e.payload['source'] ==
                SchemaLadderSource.bundledFallback.wireValue,
          ),
          isTrue,
        );
      },
    ),
    ScenarioCase(
      name: 'selector exception falls back to bundled fallback',
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(snapshotId: 'snap-1', json: _configSnapshot());

        server.stubScreen(
          screenId: 'customer_home',
          doc: const ScenarioJsonDoc(
            json: <String, Object?>{'error': true},
            statusCode: 500,
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();
        expect(vm.screen.source, ScreenLoadSource.fallback);

        final fallbackEvent = _firstEvent(
          run.sink,
          SchemaLadderEventNames.fallback,
        );
        expect(fallbackEvent, isNotNull);
        expect(
          fallbackEvent!.payload['reasonCode'],
          SchemaLadderReason.selectorException.wireValue,
        );
      },
    ),
    ScenarioCase(
      name: 'docId header is reused on 304 (cached headers)',
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(snapshotId: 'snap-1', json: _configSnapshot());

        final doc = _screenDoc(
          id: 'customer_home',
          body: const <Object?>[
            {
              'type': 'ScreenSection',
              'slots': {
                'body': [
                  {'ref': 'section:missing_fragment'},
                ],
              },
            },
          ],
        );

        server.stubScreen(
          screenId: 'customer_home',
          doc: ScenarioJsonDoc(
            json: doc,
            etag: 'E-doc',
            headers: const <String, String>{'x-daryeel-doc-id': 'doc-4'},
          ),
        );
      },
      verify: (run) async {
        final first = await run.loadInitialScreen();
        expect(first.screen.bundle.docId, 'doc-4');

        final second = await run.loadInitialScreen();
        expect(second.screen.bundle.docId, 'doc-4');

        final selectorRequests = run.server.requests
            .where((r) => r.path == '/schemas/screens/customer_home')
            .toList();

        expect(selectorRequests.length, greaterThanOrEqualTo(2));
        expect(selectorRequests.last.headers['if-none-match'], 'E-doc');

        // We intentionally don't assert repeated diagnostics events here:
        // the runtime enables TTL-based dedupe by fingerprint.

        expect(
          run.prefs.getString(
            PinnedSchemaStore.keyFor(
              product: 'customer_app',
              screenId: 'customer_home',
            ),
          ),
          isNull,
        );
      },
    ),
    ScenarioCase(
      name: 'schema compatibility overlay can force selector fallback',
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(
          snapshotId: 'snap-1',
          json: _configSnapshot(
            runtime: const <String, Object?>{
              'schemaCompatibilityPolicyOverlay': <String, Object?>{
                'supportedThemeModes': <Object?>['light'],
              },
            },
          ),
        );

        server.stubScreen(
          screenId: 'customer_home',
          doc: ScenarioJsonDoc(
            json: _screenDoc(id: 'customer_home', themeMode: 'dark'),
            headers: const <String, String>{'x-daryeel-doc-id': 'doc-overlay'},
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();
        expect(vm.screen.source, ScreenLoadSource.fallback);

        final fallbackEvent = _firstEvent(
          run.sink,
          SchemaLadderEventNames.fallback,
        );
        expect(fallbackEvent, isNotNull);
        expect(
          fallbackEvent!.payload['reasonCode'],
          SchemaLadderReason.selectorIncompatible.wireValue,
        );
      },
    ),
    ScenarioCase(
      name: 'fragment ref is resolved when fragment is served',
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(snapshotId: 'snap-1', json: _configSnapshot());

        server.stubScreen(
          screenId: 'customer_home',
          doc: ScenarioJsonDoc(
            json: _screenDoc(
              id: 'customer_home',
              body: const <Object?>[
                {
                  'type': 'ScreenSection',
                  'slots': {
                    'body': [
                      {'ref': 'section:customer_welcome_v1'},
                    ],
                  },
                },
              ],
            ),
            headers: const <String, String>{'x-daryeel-doc-id': 'doc-frag'},
          ),
        );

        server.stubFragment(
          fragmentId: 'section:customer_welcome_v1',
          doc: ScenarioJsonDoc(
            json: _fragmentDoc(
              id: 'section:customer_welcome_v1',
              node: const <String, Object?>{
                'type': 'InfoCard',
                'props': <String, Object?>{
                  'title': 'Welcome',
                  'subtitle': 'Resolved from fragment',
                },
              },
            ),
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();

        expect(vm.screen.refErrors, isEmpty);
        expect(vm.screen.schema, isNotNull);

        final root = vm.screen.schema!.root;
        final bodyNodes = root.slots['body'] ?? const <SchemaNode>[];

        bool foundWelcome = false;
        for (final node in bodyNodes) {
          if (node is ComponentNode && node.type == 'ScreenSection') {
            final sectionBody = node.slots['body'] ?? const <SchemaNode>[];
            for (final sectionNode in sectionBody) {
              if (sectionNode is ComponentNode &&
                  sectionNode.type == 'InfoCard') {
                if (sectionNode.props['title'] == 'Welcome') {
                  foundWelcome = true;
                }
              }
            }
          }
        }

        expect(foundWelcome, isTrue);
      },
    ),
    ScenarioCase(
      name: 'remote theme selector is used and pinned when enabled',
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(
          snapshotId: 'snap-1',
          json: _configSnapshot(enableRemoteThemes: true),
        );

        server.stubScreen(
          screenId: 'customer_home',
          doc: ScenarioJsonDoc(
            json: _screenDoc(id: 'customer_home'),
            headers: const <String, String>{
              'x-daryeel-doc-id': 'doc-remote-schema',
            },
          ),
        );

        server.stubTheme(
          themeId: 'customer-default',
          themeMode: 'light',
          doc: ScenarioJsonDoc(
            json: _themeDoc(themeId: 'customer-default', themeMode: 'light'),
            etag: 'T1',
            headers: const <String, String>{'x-daryeel-doc-id': 'theme-doc-1'},
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();

        expect(vm.screen.usedRemoteTheme, isTrue);
        expect(vm.screen.themeSource, ThemeLadderSource.selector);
        expect(vm.screen.themeDocId, 'theme-doc-1');

        final themeSourceUsed = _firstEvent(
          run.sink,
          ThemeLadderEventNames.sourceUsed,
        );
        expect(themeSourceUsed, isNotNull);
        expect(
          themeSourceUsed!.payload['source'],
          ThemeLadderSource.selector.wireValue,
        );
        expect(themeSourceUsed.payload['docId'], 'theme-doc-1');

        expect(
          run.prefs.getString(
            PinnedThemeStore.keyFor(
              product: 'customer_app',
              themeId: 'customer-default',
              themeMode: 'light',
            ),
          ),
          'theme-doc-1',
        );
      },
    ),
    ScenarioCase(
      name: 'config + schema feature flags are unioned',
      arrange: (server) {
        server.stubBootstrap(
          product: 'customer_app',
          json: _bootstrap(baseUrl: server.baseUrl),
        );
        server.stubSnapshot(
          snapshotId: 'snap-1',
          json: _configSnapshot(featureFlags: const <String>['from_config']),
        );

        server.stubScreen(
          screenId: 'customer_home',
          doc: ScenarioJsonDoc(
            json: _screenDoc(
              id: 'customer_home',
              featureFlags: const <Object?>['from_schema'],
            ),
            headers: const <String, String>{'x-daryeel-doc-id': 'doc-flags'},
          ),
        );
      },
      verify: (run) async {
        final vm = await run.loadInitialScreen();
        expect(
          vm.screen.enabledFeatureFlags,
          containsAll(<String>['from_config', 'from_schema']),
        );
      },
    ),
  ];

  for (final scenario in scenarios) {
    test(scenario.name, () async {
      await runScenario(scenario: scenario, buildController: _buildController);
    });
  }
}
