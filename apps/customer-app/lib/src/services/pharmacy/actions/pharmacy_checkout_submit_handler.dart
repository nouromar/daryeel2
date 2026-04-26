import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/app/runtime_session_scope.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/runtime/daryeel_runtime_session.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;

final class PharmacyCheckoutSubmitHandler {
  PharmacyCheckoutSubmitHandler({required http.Client client})
    : _client = client;

  final http.Client _client;
  final Set<String> _inFlight = <String>{};

  Future<SubmitFormResponse> submit(
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
    final orderPayload = payload['order'];
    final items = (orderPayload is Map)
        ? orderPayload['items']
        : null;
    final prescriptionAttachmentIds = (orderPayload is Map)
        ? orderPayload['prescriptionAttachmentIds']
        : null;
    final hasPrescription =
        prescriptionAttachmentIds is List && prescriptionAttachmentIds.isNotEmpty;

    final hasLines = items is List && items.isNotEmpty;
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

      await _completeSuccessfulCheckout(
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

  Future<void> _completeSuccessfulCheckout({
    required SchemaStateStore store,
    required ScaffoldMessengerState? messenger,
    required NavigatorState? navigator,
  }) {
    final completer = Completer<void>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator != null && navigator.mounted && navigator.canPop()) {
        navigator.pop();
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator != null && navigator.mounted && navigator.canPop()) {
          navigator.pop();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _clearPharmacyCheckoutState(store);
          messenger?.showSnackBar(
            const SnackBar(content: Text('Order submitted')),
          );
          if (!completer.isCompleted) {
            completer.complete();
          }
        });
        WidgetsBinding.instance.scheduleFrame();
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();

    return completer.future;
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

  static Map<String, Object?> buildPharmacyServiceRequest(
    SchemaStateStore store,
  ) {
    return <String, Object?>{
      'service_id': 'pharmacy',
      ..._buildCommonRequestFields(store),
      'order': _buildPharmacyOrderPayload(store),
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
    final items = <Map<String, Object?>>[];

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

      items.add(<String, Object?>{'productId': id, 'quantity': quantity});
    }

    final payload = <String, Object?>{'items': items};

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
        payload['prescriptionAttachmentIds'] = ids;
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
