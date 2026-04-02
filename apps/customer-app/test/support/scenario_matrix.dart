import 'dart:async';

import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scenario_server.dart';

typedef ScenarioArrange = void Function(ScenarioServer server);

typedef ScenarioBuildController =
    Future<DaryeelRuntimeController> Function(
      ScenarioServer server,
      InMemoryDiagnosticsSink sink,
    );

typedef ScenarioVerify = FutureOr<void> Function(ScenarioRun run);

class ScenarioCase {
  const ScenarioCase({
    required this.name,
    this.initialPrefs = const <String, Object>{},
    required this.arrange,
    required this.verify,
  });

  final String name;
  final Map<String, Object> initialPrefs;
  final ScenarioArrange arrange;
  final ScenarioVerify verify;
}

class ScenarioRun {
  ScenarioRun._({
    required this.server,
    required this.sink,
    required this.controller,
    required this.prefs,
  });

  final ScenarioServer server;
  final InMemoryDiagnosticsSink sink;
  final DaryeelRuntimeController controller;
  final SharedPreferences prefs;

  Future<DaryeelRuntimeViewModel> loadInitialScreen() {
    return controller.loadInitialScreen();
  }
}

Future<void> runScenario({
  required ScenarioCase scenario,
  required ScenarioBuildController buildController,
  int maxDiagnosticsEvents = 500,
}) async {
  SharedPreferences.setMockInitialValues(scenario.initialPrefs);

  final server = ScenarioServer();
  scenario.arrange(server);

  final sink = InMemoryDiagnosticsSink(maxEvents: maxDiagnosticsEvents);
  final controller = await buildController(server, sink);
  final prefs = await SharedPreferences.getInstance();

  final run = ScenarioRun._(
    server: server,
    sink: sink,
    controller: controller,
    prefs: prefs,
  );

  await scenario.verify(run);
}
