import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/app/runtime_session_scope.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/runtime/daryeel_runtime_session.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;

final class CustomerSubmitFormHandler extends SubmitFormHandler {
  CustomerSubmitFormHandler({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = (client == null);

  final http.Client _client;
  final bool _ownsClient;

  final Set<String> _inFlight = <String>{};

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
      return _submitPharmacyCheckout(context, request);
    }

    // Default behavior: accept the submit and rely on diagnostics.
    // (Other schema request flows can be wired up later.)
    return const SubmitFormResponse(ok: true);
  }

  Future<SubmitFormResponse> _submitPharmacyCheckout(
    BuildContext context,
    SubmitFormRequest request,
  ) async {
    if (_inFlight.contains(request.formId)) {
      return const SubmitFormResponse(ok: false, message: 'Already submitting');
    }

    final store = SchemaStateScope.maybeOf(context);
    if (store == null) {
      return const SubmitFormResponse(
        ok: false,
        message: 'Missing state store',
      );
    }

    final session = RuntimeSessionScope.of(context);
    final uri = _buildUri(session.apiBaseUrl, '/v1/pharmacy/orders');
    if (uri == null) {
      return const SubmitFormResponse(
        ok: false,
        message: 'API base URL is not configured',
      );
    }

    final payload = buildPharmacyServiceRequest(store);
    final pharmacyPayload = payload['payload'];
    final cartLines = (pharmacyPayload is Map)
        ? pharmacyPayload['cart_lines']
        : null;
    final prescriptionUploadIds = (pharmacyPayload is Map)
        ? pharmacyPayload['prescription_upload_ids']
        : null;
    final hasPrescription =
        prescriptionUploadIds is List && prescriptionUploadIds.isNotEmpty;

    final hasLines = cartLines is List && cartLines.isNotEmpty;
    if (!hasLines && !hasPrescription) {
      return const SubmitFormResponse(
        ok: false,
        message: 'Nothing to checkout',
      );
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.maybeOf(context);

    _inFlight.add(request.formId);
    try {
      final response = await _client.post(
        uri,
        headers: _buildHeaders(session),
        body: jsonEncode(payload),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = response.body;
        final shortBody = body.length > 300
            ? '${body.substring(0, 300)}…'
            : body;
        return SubmitFormResponse(
          ok: false,
          message: 'HTTP ${response.statusCode}: $shortBody',
        );
      }

      _scheduleSuccessfulCheckoutCompletion(
        store: store,
        messenger: messenger,
        navigator: navigator,
      );

      return const SubmitFormResponse(ok: true);
    } catch (e) {
      return SubmitFormResponse(ok: false, message: 'Checkout failed: $e');
    } finally {
      _inFlight.remove(request.formId);
    }
  }

  void _scheduleSuccessfulCheckoutCompletion({
    required SchemaStateStore store,
    required ScaffoldMessengerState? messenger,
    required NavigatorState? navigator,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearPharmacyCheckoutState(store);
      messenger?.showSnackBar(const SnackBar(content: Text('Order submitted')));
      if (navigator != null && navigator.mounted && navigator.canPop()) {
        navigator.pop();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _clearPharmacyCheckoutState(SchemaStateStore store) {
    store.setValue('pharmacy.cart.lines', const <Object?>[]);
    store.setValue('pharmacy.cart.totalQuantity', 0);
    store.setValue('pharmacy.cart.hasRxItem', false);
    store.removeValue('pharmacy.cart.prescriptionUploads');
    store.removeValue('pharmacy.checkout');
  }

  Uri? _buildUri(String baseUrl, String path) {
    final base = baseUrl.trim();
    if (base.isEmpty) return null;

    final baseUri = Uri.parse(base);
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    String mergedPath;
    if (baseUri.path.isEmpty || baseUri.path == '/') {
      mergedPath = normalizedPath;
    } else if (baseUri.path.endsWith('/') && normalizedPath.startsWith('/')) {
      mergedPath =
          '${baseUri.path.substring(0, baseUri.path.length - 1)}$normalizedPath';
    } else if (!baseUri.path.endsWith('/') && !normalizedPath.startsWith('/')) {
      mergedPath = '${baseUri.path}/$normalizedPath';
    } else {
      mergedPath = '${baseUri.path}$normalizedPath';
    }

    return baseUri.replace(path: mergedPath);
  }

  Map<String, String> _buildHeaders(DaryeelRuntimeSession session) {
    Map<String, String> extra;
    try {
      extra =
          session.requestHeadersProvider?.call() ?? const <String, String>{};
    } catch (_) {
      extra = const <String, String>{};
    }

    final correlation = session.diagnosticsReporter.buildCorrelationHeaders();

    return <String, String>{
      ...extra,
      ...correlation,
      'content-type': 'application/json',
    };
  }

  @visibleForTesting
  static Map<String, Object?> buildPharmacyServiceRequest(
    SchemaStateStore store,
  ) {
    return <String, Object?>{
      'service_id': 'pharmacy',
      ..._buildCommonRequestFields(store),
      'payload': _buildPharmacyOrderPayload(store),
    };
  }

  static Map<String, Object?> _buildCommonRequestFields(
    SchemaStateStore store,
  ) {
    final out = <String, Object?>{};

    final deliveryLocation = _readDeliveryLocation(store);
    if (deliveryLocation != null) {
      out['delivery_location'] = deliveryLocation;
    }

    final notes = _readNotes(store);
    if (notes != null) {
      out['notes'] = notes;
    }

    final payment = _readPayment(store);
    if (payment != null) {
      out['payment'] = payment;
    }

    return out;
  }

  static Map<String, Object?> _buildPharmacyOrderPayload(
    SchemaStateStore store,
  ) {
    final cartLines = <Map<String, Object?>>[];

    final rawLines = store.getValue('pharmacy.cart.lines');
    final lines = _coerceListOfStringKeyedMaps(rawLines);
    for (final line in lines) {
      final idRaw = line['id'];
      final id = (idRaw is String) ? idRaw.trim() : '${idRaw ?? ''}'.trim();
      if (id.isEmpty) continue;

      final quantityRaw = line['quantity'];
      final quantity = (quantityRaw is num)
          ? quantityRaw.toInt()
          : int.tryParse('${quantityRaw ?? ''}') ?? 0;
      if (quantity <= 0) continue;

      cartLines.add(<String, Object?>{'product_id': id, 'quantity': quantity});
    }

    final payload = <String, Object?>{'cart_lines': cartLines};

    final summaryLines = _coerceListOfStringKeyedMaps(
      store.getValue('pharmacy.cart.summary.lines'),
    );
    if (summaryLines.isNotEmpty) {
      payload['summary_lines'] = summaryLines;
    }

    final summaryTotalRaw = store.getValue('pharmacy.cart.summary.total');
    if (summaryTotalRaw is Map) {
      payload['summary_total'] = _coerceStringKeyedMap(summaryTotalRaw);
    }

    final uploadsRaw = store.getValue('pharmacy.cart.prescriptionUploads');
    if (uploadsRaw is List && uploadsRaw.isNotEmpty) {
      final ids = <String>[];
      for (final item in uploadsRaw) {
        if (item is Map) {
          final idRaw = item['id'];
          final id = (idRaw is String) ? idRaw.trim() : '';
          if (id.isNotEmpty) ids.add(id);
        }
      }
      if (ids.isNotEmpty) {
        payload['prescription_upload_ids'] = ids;
      }
    }

    return payload;
  }
}

Map<String, Object?>? _readDeliveryLocation(SchemaStateStore store) {
  final raw = store.getValue('pharmacy.cart.deliveryAddress');
  if (raw is! Map) return null;

  final location = _coerceStringKeyedMap(raw);
  final text = location['text']?.toString().trim() ?? '';
  if (text.isEmpty) return null;

  return location;
}

String? _readNotes(SchemaStateStore store) {
  final raw = store.getValue('pharmacy.checkout.notes');
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, Object?>? _readPayment(SchemaStateStore store) {
  final methodRaw = store.getValue('pharmacy.checkout.payment.method');
  final timingRaw = store.getValue('pharmacy.checkout.payment.timing');

  final method = (methodRaw is String) ? methodRaw.trim() : '';
  final timing = (timingRaw is String) ? timingRaw.trim() : '';
  if (method.isEmpty || timing.isEmpty) return null;

  return <String, Object?>{'method': method, 'timing': timing};
}

Map<String, Object?> _coerceStringKeyedMap(Map raw) {
  final out = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) continue;
    out[entry.key as String] = entry.value;
  }
  return out;
}

List<Map<String, Object?>> _coerceListOfStringKeyedMaps(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];

  final out = <Map<String, Object?>>[];
  for (final item in raw) {
    if (item is Map<String, Object?>) {
      out.add(item);
      continue;
    }
    if (item is Map) {
      final m = <String, Object?>{};
      for (final entry in item.entries) {
        if (entry.key is! String) continue;
        m[entry.key as String] = entry.value;
      }
      out.add(m);
    }
  }

  return out;
}
