import 'package:flutter_runtime/flutter_runtime.dart';

class SchemaComponentContext {
  const SchemaComponentContext({
    required this.screen,
    required this.actionDispatcher,
    required this.visibility,
    this.diagnostics,
    this.diagnosticsContext = const <String, Object?>{},
  });

  final ScreenSchema screen;
  final SchemaActionDispatcher actionDispatcher;
  final SchemaVisibilityContext visibility;
  final RuntimeDiagnostics? diagnostics;
  final Map<String, Object?> diagnosticsContext;
}
