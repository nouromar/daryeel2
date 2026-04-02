import 'package:flutter_runtime/flutter_runtime.dart';

import '../schema/customer_bootstrap_loader.dart';
import '../schema/customer_schema_compatibility.dart';

class CustomerRuntimePolicy {
  const CustomerRuntimePolicy({
    required this.compatibilityChecker,
    required this.actionPolicy,
    required this.enableRemoteThemes,
  });

  final SchemaCompatibilityChecker compatibilityChecker;
  final SchemaActionPolicy actionPolicy;
  final bool enableRemoteThemes;
}

class CustomerRuntimePolicyProvider {
  const CustomerRuntimePolicyProvider();

  CustomerRuntimePolicy build({
    required String schemaBaseUrl,
    required ConfigSnapshot? configSnapshot,
  }) {
    final schemaHost = Uri.tryParse(schemaBaseUrl)?.host;

    final compatibilityChecker = CustomerSchemaCompatibilityChecker(
      overlay: configSnapshot?.schemaCompatibilityPolicyOverlay,
    );

    final actionPolicy = SchemaActionPolicy(
      allowedActionTypes: <String>{
        SchemaActionTypes.navigate,
        SchemaActionTypes.openUrl,
        SchemaActionTypes.submitForm,
        SchemaActionTypes.trackEvent,
      },
      openUrlPolicy: UriPolicy(
        allowedSchemes: const <String>{'https'},
        allowedHosts: schemaHost == null || schemaHost.isEmpty
            ? const <String>{}
            : <String>{schemaHost},
      ),
    );

    return CustomerRuntimePolicy(
      compatibilityChecker: compatibilityChecker,
      actionPolicy: actionPolicy,
      enableRemoteThemes: configSnapshot?.enableRemoteThemes ?? false,
    );
  }
}
