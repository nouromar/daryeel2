import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/app/runtime_session_scope.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

import '../routing/customer_schema_screen_route.dart';

/// App-level action dispatcher that adds customer-app specific action types.
///
/// We keep this in the app so we can add higher-level behaviors (like cart
/// list upserts) without changing the shared runtime in `packages/*`.
final class CustomerActionDispatcher extends SchemaActionDispatcher {
  CustomerActionDispatcher({
    required this.delegate,
    Future<void> Function(
      BuildContext context,
      CustomerRequestActionCommand command,
    )?
    requestActionExecutor,
  }) : _dispatcher = TypeMapSchemaActionDispatcher(
         dispatchersByType: _buildCustomerActionDispatchersByType(
           requestActionExecutor: requestActionExecutor,
         ),
         fallback: delegate,
       );

  final SchemaActionDispatcher delegate;
  final SchemaActionDispatcher _dispatcher;

  static const String pharmacyCartUpsert = 'pharmacy_cart_upsert';
  static const String pharmacyCartIncrement = 'pharmacy_cart_increment';
  static const String pharmacyCartDecrement = 'pharmacy_cart_decrement';
  static const String pharmacyCartClear = 'pharmacy_cart_clear';
  static const String pharmacyCartRefreshSummary =
      'pharmacy_cart_refresh_summary';
  static const String customerRequestAction = 'customer_request_action';

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) =>
      _dispatcher.dispatch(context, action);
}

Map<String, SchemaActionDispatcher> _buildCustomerActionDispatchersByType({
  Future<void> Function(
    BuildContext context,
    CustomerRequestActionCommand command,
  )?
  requestActionExecutor,
}) {
  return <String, SchemaActionDispatcher>{
    CustomerActionDispatcher.pharmacyCartUpsert:
        _PharmacyCartUpsertDispatcher(),
    CustomerActionDispatcher.pharmacyCartIncrement:
        _PharmacyCartIncrementDispatcher(),
    CustomerActionDispatcher.pharmacyCartDecrement:
        _PharmacyCartDecrementDispatcher(),
    CustomerActionDispatcher.pharmacyCartClear: _PharmacyCartClearDispatcher(),
    CustomerActionDispatcher.pharmacyCartRefreshSummary:
        _PharmacyCartRefreshSummaryDispatcher(),
    CustomerActionDispatcher.customerRequestAction:
        _CustomerRequestActionDispatcher(executor: requestActionExecutor),
  };
}

enum CustomerRequestActionMode { submit, navigateUpload }

final class CustomerRequestActionCommand {
  const CustomerRequestActionCommand({
    required this.mode,
    required this.requestId,
    required this.actionId,
    this.decision,
    this.screenId,
    this.title,
  });

  final CustomerRequestActionMode mode;
  final String requestId;
  final String actionId;
  final String? decision;
  final String? screenId;
  final String? title;
}

final class _CustomerRequestActionDispatcher extends SchemaActionDispatcher {
  const _CustomerRequestActionDispatcher({this.executor});

  final Future<void> Function(
    BuildContext context,
    CustomerRequestActionCommand command,
  )?
  executor;

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    final command = _parseCustomerRequestActionCommand(context, action.value);
    final runner = executor ?? _defaultCustomerRequestActionExecutor;
    await runner(context, command);
  }
}

final class _PharmacyCartUpsertDispatcher extends SchemaActionDispatcher {
  const _PharmacyCartUpsertDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    _pharmacyCartUpsert(context, action);
  }
}

final class _PharmacyCartIncrementDispatcher extends SchemaActionDispatcher {
  const _PharmacyCartIncrementDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    _pharmacyCartChangeQuantity(context, action, delta: 1);
  }
}

final class _PharmacyCartDecrementDispatcher extends SchemaActionDispatcher {
  const _PharmacyCartDecrementDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    _pharmacyCartChangeQuantity(context, action, delta: -1);
  }
}

final class _PharmacyCartClearDispatcher extends SchemaActionDispatcher {
  const _PharmacyCartClearDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    _pharmacyCartClear(context);
  }
}

final class _PharmacyCartRefreshSummaryDispatcher
    extends SchemaActionDispatcher {
  const _PharmacyCartRefreshSummaryDispatcher();

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    _pharmacyCartRefreshSummary(context, action);
  }
}

CustomerRequestActionCommand _parseCustomerRequestActionCommand(
  BuildContext context,
  Object? raw,
) {
  if (raw is! Map) {
    throw ArgumentError('customer_request_action requires an object value');
  }

  String? readString(String key) {
    final value = raw[key];
    if (value is! String) return null;
    final resolved = interpolateSchemaString(value, context).trim();
    return resolved.isEmpty ? null : resolved;
  }

  final modeRaw = readString('mode');
  final requestId = readString('requestId');
  final actionId = readString('actionId');
  if (modeRaw == null || requestId == null || actionId == null) {
    throw ArgumentError(
      'customer_request_action requires mode, requestId, and actionId',
    );
  }

  final mode = switch (modeRaw) {
    'submit' => CustomerRequestActionMode.submit,
    'navigate_upload' => CustomerRequestActionMode.navigateUpload,
    _ => throw ArgumentError(
      'Unsupported customer_request_action mode: $modeRaw',
    ),
  };

  return CustomerRequestActionCommand(
    mode: mode,
    requestId: requestId,
    actionId: actionId,
    decision: readString('decision'),
    screenId: readString('screenId'),
    title: readString('title'),
  );
}

Future<void> _defaultCustomerRequestActionExecutor(
  BuildContext context,
  CustomerRequestActionCommand command,
) async {
  switch (command.mode) {
    case CustomerRequestActionMode.navigateUpload:
      final screenId = command.screenId;
      if (screenId == null || screenId.isEmpty) {
        throw ArgumentError('navigate_upload requires screenId');
      }
      await Navigator.of(context).pushNamed(
        CustomerSchemaScreenRoute.name,
        arguments: <String, Object?>{
          'screenId': screenId,
          'title': command.title ?? 'Upload prescription',
          'params': <String, Object?>{
            'requestId': command.requestId,
            'actionId': command.actionId,
          },
        },
      );
      return;
    case CustomerRequestActionMode.submit:
      final session = RuntimeSessionScope.of(context);
      final uri = _buildCustomerRequestActionUri(
        apiBaseUrl: session.apiBaseUrl,
        requestId: command.requestId,
        actionId: command.actionId,
      );
      if (uri == null) {
        throw StateError('API base URL is not configured');
      }

      final decision = command.decision;
      if (decision == null || decision.isEmpty) {
        throw ArgumentError('submit mode requires decision');
      }

      final headers = <String, String>{'content-type': 'application/json'};
      try {
        headers.addAll(
          session.requestHeadersProvider?.call() ?? const <String, String>{},
        );
      } catch (_) {}

      final client = http.Client();
      try {
        final response = await client.post(
          uri,
          headers: headers,
          body: jsonEncode(<String, Object?>{'decision': decision}),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final decoded = jsonDecode(response.body);
          final detail = (decoded is Map && decoded['detail'] is String)
              ? decoded['detail'] as String
              : 'HTTP ${response.statusCode}';
          throw StateError(detail);
        }
      } finally {
        client.close();
      }

      if (!context.mounted) return;
      await _refreshRequestQueries(context, requestId: command.requestId);
      return;
  }
}

Uri? _buildCustomerRequestActionUri({
  required String apiBaseUrl,
  required String requestId,
  required String actionId,
}) {
  final base = apiBaseUrl.trim();
  if (base.isEmpty) return null;
  final parsed = Uri.parse(base);
  final normalizedBasePath = parsed.path.endsWith('/')
      ? parsed.path.substring(0, parsed.path.length - 1)
      : parsed.path;
  final path = '$normalizedBasePath/v1/requests/$requestId/actions/$actionId';
  return parsed.replace(path: path);
}

Future<void> _refreshRequestQueries(
  BuildContext context, {
  required String requestId,
}) async {
  final session = RuntimeSessionScope.of(context);
  await session.queryStore.executeGet(
    key: 'customer.requests',
    path: '/v1/requests',
    forceRefresh: true,
  );
  await session.queryStore.executeGet(
    key: 'customer.request_detail',
    path: '/v1/requests/detail',
    params: <String, String>{'requestId': requestId},
    forceRefresh: true,
  );
}

const Duration _defaultPharmacyCartSummaryDebounce = Duration(
  milliseconds: 300,
);
final Map<SchemaStateStore, Timer> _pharmacyCartSummaryRefreshTimers =
    <SchemaStateStore, Timer>{};

void _pharmacyCartUpsert(BuildContext context, ActionDefinition action) {
  final store = SchemaStateScope.maybeOf(context);
  if (store == null) return;

  final raw = action.value;
  if (raw is! Map) return;

  String? readInterpolatedString(String key) {
    final v = raw[key];
    if (v is! String) return null;
    final resolved = interpolateSchemaString(v, context).trim();
    return resolved.isEmpty ? null : resolved;
  }

  double? readInterpolatedDouble(String key) {
    final v = raw[key];
    if (v is num) return v.toDouble();
    if (v is String) {
      final resolved = interpolateSchemaString(v, context).trim();
      return double.tryParse(resolved);
    }
    return null;
  }

  final id = readInterpolatedString('id');
  if (id == null) return;

  final name = readInterpolatedString('name') ?? id;
  final subtitle = readInterpolatedString('subtitle') ?? '';
  final rxRequiredRaw = readInterpolatedString('rx_required');
  final rxRequired =
      rxRequiredRaw?.trim().toLowerCase() == 'true' || rxRequiredRaw == '1';
  final price = readInterpolatedDouble('price');
  final icon = readInterpolatedString('icon');

  final nextLines = _ensureCartLines(store);

  final idx = nextLines.indexWhere((e) => (e['id'] ?? '').toString() == id);
  if (idx == -1) {
    final line = <String, Object?>{
      'id': id,
      'name': name,
      'subtitle': subtitle,
      'quantity': 1,
      'rx_required': rxRequired,
      ...?price == null ? null : <String, Object?>{'price': price},
      ...?icon == null ? null : <String, Object?>{'icon': icon},
    };
    nextLines.add(line);
  } else {
    final current = nextLines[idx];
    final qRaw = current['quantity'];
    final q = (qRaw is num) ? qRaw.toInt() : int.tryParse('$qRaw') ?? 0;
    final nextQ = q + 1;

    nextLines[idx] = <String, Object?>{
      ...current,
      'quantity': nextQ,
      // Prefer freshest catalog fields when provided.
      'name': name,
      'subtitle': subtitle,
      'rx_required': rxRequired,
      ...?price == null ? null : <String, Object?>{'price': price},
      ...?icon == null ? null : <String, Object?>{'icon': icon},
    };
  }

  store.setValue('pharmacy.cart.lines', nextLines);
  store.incrementValue('pharmacy.cart.totalQuantity', 1);
  _clampTotalQuantity(store);
  _recomputeHasRxItem(store, lines: nextLines);
  _schedulePharmacyCartSummaryRefresh(store);
}

void _pharmacyCartChangeQuantity(
  BuildContext context,
  ActionDefinition action, {
  required int delta,
}) {
  final store = SchemaStateScope.maybeOf(context);
  if (store == null) return;

  final raw = action.value;
  if (raw is! Map) return;

  final idTemplate = raw['id'];
  final id = (idTemplate is String)
      ? interpolateSchemaString(idTemplate, context).trim()
      : null;
  if (id == null || id.isEmpty) return;

  final nextLines = _ensureCartLines(store);
  final idx = nextLines.indexWhere((e) => (e['id'] ?? '').toString() == id);
  if (idx == -1) return;

  final current = nextLines[idx];
  final qRaw = current['quantity'];
  final q = (qRaw is num) ? qRaw.toInt() : int.tryParse('$qRaw') ?? 0;
  final nextQ = q + delta;

  if (nextQ <= 0) {
    nextLines.removeAt(idx);
  } else {
    nextLines[idx] = <String, Object?>{...current, 'quantity': nextQ};
  }

  store.setValue('pharmacy.cart.lines', nextLines);
  store.incrementValue('pharmacy.cart.totalQuantity', delta);
  _clampTotalQuantity(store);
  _recomputeHasRxItem(store, lines: nextLines);
  _schedulePharmacyCartSummaryRefresh(store, immediate: nextLines.isEmpty);
}

void _pharmacyCartClear(BuildContext context) {
  final store = SchemaStateScope.maybeOf(context);
  if (store == null) return;

  store.setValue('pharmacy.cart.lines', const <Object?>[]);
  store.setValue('pharmacy.cart.totalQuantity', 0);
  store.setValue('pharmacy.cart.hasRxItem', false);
  store.removeValue('pharmacy.cart.prescriptionUploads');

  _cancelPharmacyCartSummaryRefresh(store);
  _applyPharmacyCartSummary(store);
}

void _pharmacyCartRefreshSummary(
  BuildContext context,
  ActionDefinition action,
) {
  final store = SchemaStateScope.maybeOf(context);
  if (store == null) return;

  var immediate = false;
  var debounceMs = _defaultPharmacyCartSummaryDebounce.inMilliseconds;

  final raw = action.value;
  if (raw is Map) {
    final immediateRaw = raw['immediate'];
    if (immediateRaw is bool) immediate = immediateRaw;

    final debounceRaw = raw['debounceMs'];
    if (debounceRaw is num) {
      debounceMs = debounceRaw.toInt();
    } else if (debounceRaw is String) {
      debounceMs = int.tryParse(debounceRaw.trim()) ?? debounceMs;
    }
  }

  _schedulePharmacyCartSummaryRefresh(
    store,
    immediate: immediate || debounceMs <= 0,
    debounce: Duration(milliseconds: debounceMs.clamp(0, 5000)),
  );
}

List<Map<String, Object?>> _ensureCartLines(SchemaStateStore store) {
  final raw = store.getValue('pharmacy.cart.lines');
  if (raw is List) {
    final out = <Map<String, Object?>>[];
    for (final e in raw) {
      if (e is Map) {
        final m = <String, Object?>{};
        for (final entry in e.entries) {
          if (entry.key is! String) continue;
          m[entry.key as String] = entry.value;
        }
        out.add(m);
      }
    }
    return out;
  }

  store.setValue('pharmacy.cart.lines', const <Object?>[]);
  return <Map<String, Object?>>[];
}

void _clampTotalQuantity(SchemaStateStore store) {
  final raw = store.getValue('pharmacy.cart.totalQuantity');
  final current = (raw is num) ? raw.toInt() : int.tryParse('$raw') ?? 0;
  if (current < 0) store.setValue('pharmacy.cart.totalQuantity', 0);
}

void _recomputeHasRxItem(
  SchemaStateStore store, {
  required List<Map<String, Object?>> lines,
}) {
  var hasRx = false;
  for (final line in lines) {
    final qRaw = line['quantity'];
    final q = (qRaw is num) ? qRaw.toInt() : int.tryParse('$qRaw') ?? 0;
    if (q <= 0) continue;

    final rxRaw = line['rx_required'];
    final rx =
        rxRaw == true ||
        (rxRaw is String && rxRaw.trim().toLowerCase() == 'true');
    if (rx) {
      hasRx = true;
      break;
    }
  }
  store.setValue('pharmacy.cart.hasRxItem', hasRx);
}

double? _readLineUnitPrice(Map data) {
  final raw = data['price'] ?? data['unitPrice'];
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim());
  final subtitle = (data['subtitle'] ?? '').toString();
  return _tryParseMoney(subtitle);
}

void _schedulePharmacyCartSummaryRefresh(
  SchemaStateStore store, {
  bool immediate = false,
  Duration debounce = _defaultPharmacyCartSummaryDebounce,
}) {
  _cancelPharmacyCartSummaryRefresh(store);

  if (immediate || debounce <= Duration.zero) {
    _applyPharmacyCartSummary(store);
    return;
  }

  store.setValue('pharmacy.cart.summary.isRefreshing', true);
  _pharmacyCartSummaryRefreshTimers[store] = Timer(debounce, () {
    _applyPharmacyCartSummary(store);
    _pharmacyCartSummaryRefreshTimers.remove(store);
  });
}

void _cancelPharmacyCartSummaryRefresh(SchemaStateStore store) {
  final timer = _pharmacyCartSummaryRefreshTimers[store];
  timer?.cancel();
  _pharmacyCartSummaryRefreshTimers.remove(store);
}

void _applyPharmacyCartSummary(SchemaStateStore store) {
  final lines = _ensureCartLines(store);
  const currencySymbol = r'$';

  var subtotal = 0.0;
  for (final line in lines) {
    final quantityRaw = line['quantity'];
    final quantity = (quantityRaw is num)
        ? quantityRaw.toInt()
        : int.tryParse('$quantityRaw') ?? 0;
    if (quantity <= 0) continue;

    final unitPrice = _readLineUnitPrice(line);
    if (unitPrice == null) continue;
    subtotal += unitPrice * quantity;
  }

  final tax = _readNumericState(store, 'pharmacy.cart.tax');
  final discount = _readNumericState(store, 'pharmacy.cart.discount');
  final total = subtotal + tax - discount;

  store.setValue('pharmacy.cart.subtotal', subtotal);
  store.setValue('pharmacy.cart.summary.lines', <Object?>[
    <String, Object?>{
      'id': 'subtotal',
      'label': 'Subtotal',
      'amount': subtotal,
      'amountText': _formatMoneyValue(subtotal, currencySymbol),
      'kind': 'default',
      'emphasis': 'normal',
    },
    <String, Object?>{
      'id': 'tax',
      'label': 'Tax',
      'amount': tax,
      'amountText': _formatMoneyValue(tax, currencySymbol),
      'kind': 'tax',
      'emphasis': 'muted',
    },
    <String, Object?>{
      'id': 'discount',
      'label': 'Discount',
      'amount': discount,
      'amountText': '-${_formatMoneyValue(discount, currencySymbol)}',
      'kind': 'discount',
      'emphasis': 'strong',
    },
  ]);
  store.setValue('pharmacy.cart.summary.total', <String, Object?>{
    'label': 'Total',
    'amount': total,
    'amountText': _formatMoneyValue(total, currencySymbol),
    'kind': 'total',
    'emphasis': 'strong',
  });
  store.setValue('pharmacy.cart.summary.isRefreshing', false);
  store.setValue(
    'pharmacy.cart.summary.lastUpdatedAt',
    DateTime.now().toUtc().toIso8601String(),
  );
}

double _readNumericState(SchemaStateStore store, String key) {
  final raw = store.getValue(key);
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? 0.0;
  return 0.0;
}

double? _tryParseMoney(String text) {
  final input = text.trim();
  if (input.isEmpty) return null;

  final match = RegExp(r'\$\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(input);
  if (match == null) return null;
  return double.tryParse(match.group(1) ?? '');
}

String _formatMoneyValue(double amount, String currencySymbol) {
  return '$currencySymbol${amount.toStringAsFixed(2)}';
}
