import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'SubmitFormSchemaActionDispatcher reads values and applies field errors',
      (tester) async {
    final store = SchemaFormStore();
    store.setFieldValue('request_form', 'pickup_address', 'A');

    final responseCompleter = Completer<SubmitFormResponse>();
    final handler = _ControlledSubmitFormHandler(responseCompleter);
    final dispatcher = SubmitFormSchemaActionDispatcher(
      submitFormHandler: handler,
    );

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: SchemaFormScope(
          store: store,
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final action = ActionDefinition(
      type: SchemaActionTypes.submitForm,
      formId: 'request_form',
    );

    final future = dispatcher.dispatch(ctx, action);
    await tester.pump();

    expect(store.snapshot('request_form').isSubmitting, isTrue);
    expect(handler.last?.formId, 'request_form');
    expect(handler.last?.values['pickup_address'], 'A');

    responseCompleter.complete(
      const SubmitFormResponse(
        ok: true,
        fieldErrors: <String, String>{'pickup_address': 'invalid'},
      ),
    );

    await future;
    await tester.pump();

    final snapshot = store.snapshot('request_form');
    expect(snapshot.isSubmitting, isFalse);
    expect(snapshot.fieldErrors['pickup_address'], 'invalid');
  });

  testWidgets('SubmitFormSchemaActionDispatcher resets submitting on failure',
      (tester) async {
    final store = SchemaFormStore();

    final responseCompleter = Completer<SubmitFormResponse>();
    final handler = _ControlledSubmitFormHandler(responseCompleter);
    final dispatcher = SubmitFormSchemaActionDispatcher(
      submitFormHandler: handler,
    );

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: SchemaFormScope(
          store: store,
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final action = ActionDefinition(
      type: SchemaActionTypes.submitForm,
      formId: 'request_form',
    );

    final future = dispatcher.dispatch(ctx, action);
    await tester.pump();
    expect(store.snapshot('request_form').isSubmitting, isTrue);

    responseCompleter.complete(
      const SubmitFormResponse(ok: false, message: 'nope'),
    );

    await expectLater(() => future, throwsA(isA<StateError>()));
    expect(store.snapshot('request_form').isSubmitting, isFalse);
  });

  testWidgets('SubmitFormSchemaActionDispatcher validates form before submit',
      (tester) async {
    final store = SchemaFormStore();
    store.registerFieldValidation(
      'request_form',
      'pickup_address',
      const SchemaFieldValidationRules(required: true, minLength: 2),
    );

    final handler = _ControlledSubmitFormHandler(
      Completer<SubmitFormResponse>(),
    );
    final dispatcher = SubmitFormSchemaActionDispatcher(
      submitFormHandler: handler,
    );

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: SchemaFormScope(
          store: store,
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final action = ActionDefinition(
      type: SchemaActionTypes.submitForm,
      formId: 'request_form',
    );

    await dispatcher.dispatch(ctx, action);
    await tester.pump();

    // No handler call, not submitting.
    expect(handler.last, isNull);
    expect(store.snapshot('request_form').isSubmitting, isFalse);
    expect(store.snapshot('request_form').fieldErrors['pickup_address'],
        isNotNull);
  });
}

class _ControlledSubmitFormHandler extends SubmitFormHandler {
  _ControlledSubmitFormHandler(this._responseCompleter);

  final Completer<SubmitFormResponse> _responseCompleter;
  SubmitFormRequest? last;

  @override
  Future<SubmitFormResponse> submit(
    BuildContext context,
    SubmitFormRequest request,
  ) async {
    last = request;
    return _responseCompleter.future;
  }
}
