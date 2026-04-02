import 'package:flutter/widgets.dart';
import 'package:schema_runtime_dart/schema_runtime_dart.dart';

import '../forms/schema_form_store.dart';
import 'action_dispatcher.dart';
import 'action_policy.dart';

final class SubmitFormRequest {
  const SubmitFormRequest({
    required this.formId,
    required this.values,
  });

  final String formId;
  final Map<String, Object?> values;
}

final class SubmitFormResponse {
  const SubmitFormResponse({
    required this.ok,
    this.message,
    this.fieldErrors = const <String, String>{},
  });

  final bool ok;
  final String? message;
  final Map<String, String> fieldErrors;
}

abstract class SubmitFormHandler {
  const SubmitFormHandler();

  Future<SubmitFormResponse> submit(
    BuildContext context,
    SubmitFormRequest request,
  );
}

/// Dispatcher for `submit_form` actions.
///
/// Reads the current [SchemaFormStore] values for the given `formId`, validates
/// the form, then calls the injected [SubmitFormHandler].
final class SubmitFormSchemaActionDispatcher extends SchemaActionDispatcher {
  const SubmitFormSchemaActionDispatcher({required this.submitFormHandler});

  final SubmitFormHandler submitFormHandler;

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    if (action.type != SchemaActionTypes.submitForm) {
      throw UnsupportedError('Unsupported action type: ${action.type}');
    }

    final formId = action.formId;
    if (formId == null || formId.isEmpty) {
      throw ArgumentError.value(formId, 'action.formId', 'Missing formId');
    }

    final store = SchemaFormScope.of(context);

    final valid = store.validateForm(formId);
    if (!valid) {
      return;
    }

    store.setSubmitting(formId, true);
    try {
      final request = SubmitFormRequest(
        formId: formId,
        values: store.snapshotValues(formId),
      );

      final response = await submitFormHandler.submit(context, request);

      if (response.fieldErrors.isNotEmpty) {
        store.setFieldErrors(formId, response.fieldErrors);
      } else {
        store.clearFieldErrors(formId);
      }

      if (!response.ok) {
        throw StateError(response.message ?? 'Form submission failed');
      }
    } finally {
      store.setSubmitting(formId, false);
    }
  }
}
