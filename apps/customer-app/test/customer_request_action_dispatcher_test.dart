import 'package:customer_app/src/actions/customer_action_dispatcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('customer_request_action parses submit values', (tester) async {
    late BuildContext captured;
    CustomerRequestActionCommand? command;

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaDataScope(
          data: const <String, Object?>{
            'request': <String, Object?>{'id': '42'},
            'item': <String, Object?>{'id': 'confirm_price'},
          },
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final dispatcher = CustomerActionDispatcher(
      delegate: const UnsupportedSchemaActionDispatcher(),
      requestActionExecutor: (context, next) async {
        command = next;
      },
    );

    await dispatcher.dispatch(
      captured,
      const ActionDefinition(
        type: CustomerActionDispatcher.customerRequestAction,
        value: <String, Object?>{
          'mode': 'submit',
          'requestId': '42',
          'actionId': 'confirm_price',
          'decision': 'approve',
        },
      ),
    );

    expect(command, isNotNull);
    expect(command!.mode, CustomerRequestActionMode.submit);
    expect(command!.requestId, '42');
    expect(command!.actionId, 'confirm_price');
    expect(command!.decision, 'approve');
  });

  testWidgets('customer_request_action parses upload navigation values', (
    tester,
  ) async {
    late BuildContext captured;
    CustomerRequestActionCommand? command;

    await tester.pumpWidget(
      MaterialApp(
        home: SchemaDataScope(
          data: const <String, Object?>{
            'request': <String, Object?>{'id': '99'},
            'item': <String, Object?>{'id': 'upload_prescription'},
          },
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final dispatcher = CustomerActionDispatcher(
      delegate: const UnsupportedSchemaActionDispatcher(),
      requestActionExecutor: (context, next) async {
        command = next;
      },
    );

    await dispatcher.dispatch(
      captured,
      const ActionDefinition(
        type: CustomerActionDispatcher.customerRequestAction,
        value: <String, Object?>{
          'mode': 'navigate_upload',
          'requestId': '99',
          'actionId': 'upload_prescription',
          'screenId': 'pharmacy_prescription_upload',
          'title': 'Upload prescription',
        },
      ),
    );

    expect(command, isNotNull);
    expect(command!.mode, CustomerRequestActionMode.navigateUpload);
    expect(command!.requestId, '99');
    expect(command!.actionId, 'upload_prescription');
    expect(command!.screenId, 'pharmacy_prescription_upload');
  });
}
