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

    final payload = _buildPharmacyOrderPayload(store);
    final cartLines = payload['cart_lines'];
    final hasPrescription =
        payload['prescription_upload_id'] != null ||
        (payload['prescription_upload_ids'] is List &&
            (payload['prescription_upload_ids'] as List).isNotEmpty);

    final hasLines = cartLines is List && cartLines.isNotEmpty;
    if (!hasLines && !hasPrescription) {
      return const SubmitFormResponse(
        ok: false,
        message: 'Nothing to checkout',
      );
    }

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

      store.setValue('pharmacy.cart.lines', const <Object?>[]);
      store.setValue('pharmacy.cart.totalQuantity', 0);
      store.setValue('pharmacy.cart.hasRxItem', false);
      store.removeValue('pharmacy.cart.prescriptionUploadId');
      store.removeValue('pharmacy.cart.prescriptionUploads');

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Order submitted')));
        Navigator.of(context).pop();
      }

      return const SubmitFormResponse(ok: true);
    } catch (e) {
      return SubmitFormResponse(ok: false, message: 'Checkout failed: $e');
    } finally {
      _inFlight.remove(request.formId);
    }
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

  Map<String, Object?> _buildPharmacyOrderPayload(SchemaStateStore store) {
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
    } else {
      final prescriptionUploadIdRaw = store.getValue(
        'pharmacy.cart.prescriptionUploadId',
      );
      final prescriptionUploadId = (prescriptionUploadIdRaw is String)
          ? prescriptionUploadIdRaw.trim()
          : '';
      if (prescriptionUploadId.isNotEmpty) {
        payload['prescription_upload_id'] = prescriptionUploadId;
      }
    }

    return payload;
  }
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
