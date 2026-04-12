import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;

import '../services/pharmacy/actions/pharmacy_checkout_submit_handler.dart';

final class CustomerSubmitFormHandler extends SubmitFormHandler {
  CustomerSubmitFormHandler({http.Client? client})
    : this._(client: client ?? http.Client(), ownsClient: client == null);

  CustomerSubmitFormHandler._({
    required http.Client client,
    required bool ownsClient,
  }) : _client = client,
       _ownsClient = ownsClient,
       _pharmacyCheckoutHandler = PharmacyCheckoutSubmitHandler(client: client);

  final http.Client _client;
  final bool _ownsClient;
  final PharmacyCheckoutSubmitHandler _pharmacyCheckoutHandler;

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  @override
  Future<SubmitFormResponse> submit(
    BuildContext context,
    SubmitFormRequest request,
  ) async {
    if (request.formId == 'pharmacy_checkout') {
      return _pharmacyCheckoutHandler.submit(context, request);
    }

    // Default behavior: accept the submit and rely on diagnostics.
    // (Other schema request flows can be wired up later.)
    return const SubmitFormResponse(ok: true);
  }

  @visibleForTesting
  static Map<String, Object?> buildPharmacyServiceRequest(
    SchemaStateStore store,
  ) {
    return PharmacyCheckoutSubmitHandler.buildPharmacyServiceRequest(store);
  }
}
