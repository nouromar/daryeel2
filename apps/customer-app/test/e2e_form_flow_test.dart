import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/src/ui/customer_component_registry.dart';

final class _CapturingSubmitFormHandler extends SubmitFormHandler {
  _CapturingSubmitFormHandler({required this.inner, required this.onSubmit});

  final SubmitFormHandler inner;
  final void Function(SubmitFormRequest request) onSubmit;

  @override
  Future<SubmitFormResponse> submit(
    BuildContext context,
    SubmitFormRequest request,
  ) async {
    onSubmit(request);
    return inner.submit(context, request);
  }
}

void main() {
  testWidgets('Schema TextInput binds, validates, and submits', (tester) async {
    final diagnosticsSink = InMemoryDiagnosticsSink();
    final diagnostics = BudgetedRuntimeDiagnostics(sink: diagnosticsSink);

    final formStore = SchemaFormStore();
    SubmitFormRequest? lastRequest;

    final diagnosticsContext = <String, Object?>{'test': true};

    final submitHandler = _CapturingSubmitFormHandler(
      inner: DiagnosticsSubmitFormHandler(
        diagnostics: diagnostics,
        diagnosticsContext: diagnosticsContext,
      ),
      onSubmit: (req) => lastRequest = req,
    );

    final actionDispatcher = TypeMapSchemaActionDispatcher(
      dispatchersByType: <String, SchemaActionDispatcher>{
        SchemaActionTypes.submitForm: SubmitFormSchemaActionDispatcher(
          submitFormHandler: submitHandler,
        ),
      },
      fallback: const UnsupportedSchemaActionDispatcher(),
    );

    final schemaJson = <String, Object?>{
      'schemaVersion': '1.0',
      'documentType': 'screen',
      'product': 'customer_app',
      'id': 'test.form',
      'themeId': 'customer',
      'root': <String, Object?>{
        'type': 'ScreenTemplate',
        'props': const <String, Object?>{},
        'actions': const <String, Object?>{},
        'slots': <String, Object?>{
          'body': <Object?>[
            <String, Object?>{
              'type': 'TextInput',
              'bind': 'checkout.name',
              'props': <String, Object?>{
                'label': 'Name',
                'hint': 'Enter name',
                'testId': 'name',
                'validation': <String, Object?>{'required': true},
              },
              'actions': const <String, Object?>{},
              'slots': const <String, Object?>{},
            },
          ],
          'footer': <Object?>[
            <String, Object?>{
              'type': 'PrimaryActionBar',
              'props': const <String, Object?>{'primaryLabel': 'Submit'},
              'actions': const <String, Object?>{'primary': 'submit1'},
              'slots': const <String, Object?>{},
            },
          ],
        },
      },
      'actions': <String, Object?>{
        'submit1': <String, Object?>{
          'type': SchemaActionTypes.submitForm,
          'formId': 'checkout',
        },
      },
    };

    final parsed = parseScreenSchema(schemaJson);
    expect(parsed.errors, isEmpty);
    final screen = parsed.value!;

    final registry = buildCustomerComponentRegistry(
      screen: screen,
      actionDispatcher: actionDispatcher,
      visibility: SchemaVisibilityContext(
        enabledFeatureFlags: const <String>{},
        service: screen.service,
        state: const <String, Object?>{},
      ),
      diagnostics: diagnostics,
      diagnosticsContext: diagnosticsContext,
    );

    final renderer = SchemaRenderer(rootNode: screen.root, registry: registry);

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaFormScope(
          store: formStore,
          child: Scaffold(body: renderer.render()),
        ),
      ),
    );

    // Empty submit => validation error.
    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
    expect(lastRequest, isNull);

    // Enter text clears error and allows submit.
    await tester.enterText(
      find.byKey(const ValueKey('schema.textinput.name')),
      'Asha',
    );
    await tester.pump();
    expect(find.text('Required'), findsNothing);

    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(lastRequest?.formId, 'checkout');
    expect(lastRequest?.values['name'], 'Asha');

    final formEvents = diagnosticsSink.events
        .where((e) => e.eventName == 'runtime.form.submit')
        .toList(growable: false);
    expect(formEvents.length, 1);

    final payloadJson = jsonEncode(formEvents.single.payload);
    expect(payloadJson.contains('name'), isTrue);
    expect(payloadJson.contains('Asha'), isFalse);
  });
}
