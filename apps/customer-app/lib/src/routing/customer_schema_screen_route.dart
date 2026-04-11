import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

/// Single stable route that can render any schema screen by id.
///
/// Contract (Navigator arguments):
/// ```json
/// {
///   "screenId": "pharmacy_shop",
///   "title": "Pharmacy",
///   "service": "pharmacy",
///   "chromePreset": "pharmacy_cart_badge",
///   "params": {"foo": "bar"}
/// }
/// ```
///
/// For convenience, if `params` is omitted, any extra top-level keys besides
/// the reserved keys are treated as route params.
class CustomerSchemaScreenRoute {
  static const name = 'customer.schema_screen';

  static WidgetBuilder builder() {
    return (context) {
      final rawArgs = ModalRoute.of(context)?.settings.arguments;
      final request = CustomerSchemaScreenRouteRequest.tryParse(rawArgs);
      if (request == null) {
        return _InvalidRouteArgsScreen(rawArgs: rawArgs);
      }

      return SchemaRoutedScreen(
        screenId: request.screenId,
        service: request.service,
        title: request.title,
        routeParams: request.params,
        appBarActionsBuilder:
            CustomerSchemaChromePresets.resolveAppBarActionsBuilder(
              preset: request.chromePreset,
            ),
      );
    };
  }
}

enum CustomerChromePreset { standard, pharmacyCartBadge }

final class CustomerSchemaChromePresets {
  static CustomerChromePreset parse(String? raw) {
    switch (raw) {
      case null:
      case '':
      case 'standard':
        return CustomerChromePreset.standard;
      case 'pharmacy_cart_badge':
        return CustomerChromePreset.pharmacyCartBadge;
      default:
        // Guardrail: fail-closed to standard chrome.
        return CustomerChromePreset.standard;
    }
  }

  static SchemaRoutedScreenAppBarActionsBuilder? resolveAppBarActionsBuilder({
    required CustomerChromePreset preset,
  }) {
    switch (preset) {
      case CustomerChromePreset.standard:
        return null;
      case CustomerChromePreset.pharmacyCartBadge:
        return _pharmacyCartBadge;
    }
  }

  static List<Widget> _pharmacyCartBadge(BuildContext context, LoadedScreen _) {
    final store = SchemaStateScope.maybeOf(context);
    if (store == null) {
      return <Widget>[
        IconButton(
          onPressed: null,
          icon: const Icon(Icons.shopping_cart_outlined),
        ),
      ];
    }

    return <Widget>[
      AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final rawItems = store.getValue('pharmacy.cart.totalQuantity');
          final items = (rawItems is num)
              ? rawItems.toInt()
              : int.tryParse('${rawItems ?? ''}') ?? 0;

          final uploadsRaw = store.getValue(
            'pharmacy.cart.prescriptionUploads',
          );
          final uploadsCount = (uploadsRaw is List) ? uploadsRaw.length : 0;
          final prescriptions = uploadsCount;

          final show = items > 0 || prescriptions > 0;
          final total = items + prescriptions;
          final labelText = '$total';

          final colors = Theme.of(context).colorScheme;

          final icon = show
              ? Badge(
                  backgroundColor: colors.primary,
                  textColor: colors.onPrimary,
                  label: Text(labelText),
                  child: const Icon(Icons.shopping_cart_outlined),
                )
              : const Icon(Icons.shopping_cart_outlined);

          return IconButton(
            icon: icon,
            onPressed: () {
              Navigator.of(context).pushNamed(
                CustomerSchemaScreenRoute.name,
                arguments: const <String, Object?>{
                  'screenId': 'pharmacy_cart',
                  'title': 'Cart',
                  'chromePreset': 'standard',
                },
              );
            },
          );
        },
      ),
    ];
  }
}

final class CustomerSchemaScreenRouteRequest {
  CustomerSchemaScreenRouteRequest({
    required this.screenId,
    required this.title,
    required this.service,
    required this.chromePreset,
    required this.params,
  });

  final String screenId;
  final String? title;
  final String? service;
  final CustomerChromePreset chromePreset;
  final Map<String, Object?> params;

  static const int _maxArgsBytes = 16 * 1024;
  static const int _maxParamsKeys = 50;
  static const int _maxStringLength = 120;
  static const int _maxDepth = 4;

  static final RegExp _screenIdRe = RegExp(r'^[a-z][a-z0-9_\-.]{0,79}$');

  static CustomerSchemaScreenRouteRequest? tryParse(Object? raw) {
    final args = _coerceMap(raw);
    if (args == null || args.isEmpty) return null;

    // Quick size gate.
    if (!_withinJsonByteBudget(args, maxBytes: _maxArgsBytes)) {
      return null;
    }

    final screenIdRaw = args['screenId'];
    final screenId = (screenIdRaw is String) ? screenIdRaw.trim() : '';
    if (screenId.isEmpty || !_screenIdRe.hasMatch(screenId)) {
      return null;
    }

    final titleRaw = args['title'];
    final title = (titleRaw is String)
        ? (() {
            final bounded = _boundedString(titleRaw);
            return bounded.isEmpty ? null : bounded;
          })()
        : null;

    final serviceRaw = args['service'];
    final service = (serviceRaw is String)
        ? (() {
            final bounded = _boundedString(serviceRaw);
            return bounded.isEmpty ? null : bounded;
          })()
        : null;

    final chromeRaw = args['chromePreset'];
    final chromePreset = CustomerSchemaChromePresets.parse(
      chromeRaw is String ? chromeRaw.trim() : null,
    );

    final paramsCandidate = _extractParamsCandidate(args);
    final params = _sanitizeJsonishMap(
      paramsCandidate,
      maxDepth: _maxDepth,
      maxKeys: _maxParamsKeys,
    );

    return CustomerSchemaScreenRouteRequest(
      screenId: screenId,
      title: title,
      service: service,
      chromePreset: chromePreset,
      params: params,
    );
  }

  static Map<String, Object?> _extractParamsCandidate(
    Map<String, Object?> args,
  ) {
    final rawParams = args['params'];
    final fromParamsKey = _coerceMap(rawParams);
    if (fromParamsKey != null) return fromParamsKey;

    // If `params` isn't provided, treat extra keys as params.
    const reserved = <String>{'screenId', 'title', 'service', 'chromePreset'};
    final out = <String, Object?>{};
    for (final entry in args.entries) {
      if (reserved.contains(entry.key)) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }

  static String _boundedString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= _maxStringLength) return trimmed;
    return trimmed.substring(0, _maxStringLength);
  }
}

class _InvalidRouteArgsScreen extends StatelessWidget {
  const _InvalidRouteArgsScreen({required this.rawArgs});

  final Object? rawArgs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invalid route arguments')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Unable to parse schema route arguments.\n\n'
          'Expected a JSON object with at least: {"screenId": "..."}.\n\n'
          'Received: ${rawArgs.runtimeType}\n$rawArgs',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

Map<String, Object?>? _coerceMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) continue;
      out[entry.key as String] = entry.value;
    }
    return out;
  }
  return null;
}

bool _withinJsonByteBudget(Map<String, Object?> raw, {required int maxBytes}) {
  try {
    final encoded = jsonEncode(raw);
    return utf8.encode(encoded).length <= maxBytes;
  } catch (_) {
    return false;
  }
}

Map<String, Object?> _sanitizeJsonishMap(
  Map<String, Object?> input, {
  required int maxDepth,
  required int maxKeys,
}) {
  final out = <String, Object?>{};
  if (maxKeys <= 0) return out;

  var used = 0;
  for (final entry in input.entries) {
    if (used >= maxKeys) break;
    final key = entry.key.trim();
    if (key.isEmpty) continue;

    out[key] = _sanitizeJsonishValue(entry.value, depth: 0, maxDepth: maxDepth);
    used++;
  }
  return out;
}

Object? _sanitizeJsonishValue(
  Object? value, {
  required int depth,
  required int maxDepth,
}) {
  if (value == null) return null;
  if (value is String || value is num || value is bool) return value;

  if (depth >= maxDepth) {
    // Guardrail: prevent deep/unbounded objects.
    return null;
  }

  if (value is List) {
    return value
        .take(100)
        .map(
          (e) => _sanitizeJsonishValue(e, depth: depth + 1, maxDepth: maxDepth),
        )
        .toList(growable: false);
  }

  if (value is Map) {
    final out = <String, Object?>{};
    var used = 0;
    for (final entry in value.entries) {
      if (used >= 50) break;
      if (entry.key is! String) continue;
      final k = (entry.key as String).trim();
      if (k.isEmpty) continue;
      out[k] = _sanitizeJsonishValue(
        entry.value,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
      used++;
    }
    return out;
  }

  // Everything else is rejected.
  return null;
}
