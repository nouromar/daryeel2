import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

/// App-level action dispatcher that adds customer-app specific action types.
///
/// We keep this in the app so we can add higher-level behaviors (like cart
/// list upserts) without changing the shared runtime in `packages/*`.
final class CustomerActionDispatcher extends SchemaActionDispatcher {
  CustomerActionDispatcher({required this.delegate})
    : _dispatcher = TypeMapSchemaActionDispatcher(
        dispatchersByType: _customerActionDispatchersByType,
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

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) =>
      _dispatcher.dispatch(context, action);
}

const Map<String, SchemaActionDispatcher>
_customerActionDispatchersByType = <String, SchemaActionDispatcher>{
  CustomerActionDispatcher.pharmacyCartUpsert: _PharmacyCartUpsertDispatcher(),
  CustomerActionDispatcher.pharmacyCartIncrement:
      _PharmacyCartIncrementDispatcher(),
  CustomerActionDispatcher.pharmacyCartDecrement:
      _PharmacyCartDecrementDispatcher(),
  CustomerActionDispatcher.pharmacyCartClear: _PharmacyCartClearDispatcher(),
  CustomerActionDispatcher.pharmacyCartRefreshSummary:
      _PharmacyCartRefreshSummaryDispatcher(),
};

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

  bool readInterpolatedBool(String key, {required bool fallback}) {
    final v = raw[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final resolved = interpolateSchemaString(v, context).trim().toLowerCase();
      if (resolved == 'true' || resolved == '1' || resolved == 'yes') {
        return true;
      }
      if (resolved == 'false' || resolved == '0' || resolved == 'no') {
        return false;
      }
    }
    return fallback;
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

  final title = readInterpolatedString('title') ?? id;
  final subtitle = readInterpolatedString('subtitle') ?? '';
  final rxRequired = readInterpolatedBool('rxRequired', fallback: false);
  final unitPrice = readInterpolatedDouble('unitPrice');
  final currencySymbol = readInterpolatedString('currencySymbol') ?? r'$';

  final nextLines = _ensureCartLines(store);

  final idx = nextLines.indexWhere((e) => (e['id'] ?? '').toString() == id);
  if (idx == -1) {
    nextLines.add(
      _buildCartLine(
        id: id,
        title: title,
        subtitle: subtitle,
        rxRequired: rxRequired,
        quantity: 1,
        unitPrice: unitPrice,
        currencySymbol: currencySymbol,
      ),
    );
  } else {
    final current = nextLines[idx];
    final qRaw = current['quantity'];
    final q = (qRaw is num) ? qRaw.toInt() : int.tryParse('$qRaw') ?? 0;
    final nextQ = q + 1;

    nextLines[idx] = _buildCartLine(
      id: id,
      title: title,
      subtitle: subtitle,
      rxRequired: rxRequired,
      quantity: nextQ,
      unitPrice: unitPrice ?? _readLineUnitPrice(current),
      currencySymbol: current['currencySymbol']?.toString() ?? currencySymbol,
      existing: current,
    );
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
    final subtitle = (current['subtitle'] ?? '').toString();
    final rxRaw = current['rxRequired'];
    final rxRequired =
        rxRaw == true ||
        (rxRaw is String && rxRaw.trim().toLowerCase() == 'true');

    nextLines[idx] = _buildCartLine(
      id: (current['id'] ?? '').toString(),
      title: (current['title'] ?? '').toString(),
      subtitle: subtitle,
      rxRequired: rxRequired,
      quantity: nextQ,
      unitPrice: _readLineUnitPrice(current),
      currencySymbol: current['currencySymbol']?.toString() ?? r'$',
      existing: current,
    );
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

    final rxRaw = line['rxRequired'];
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

Map<String, Object?> _buildCartLine({
  required String id,
  required String title,
  required String subtitle,
  required bool rxRequired,
  required int quantity,
  required double? unitPrice,
  required String currencySymbol,
  Map<String, Object?>? existing,
}) {
  final normalizedCurrencySymbol = currencySymbol.trim().isEmpty
      ? r'$'
      : currencySymbol.trim();
  final safeQuantity = quantity < 0 ? 0 : quantity;
  final unitPriceText = unitPrice == null
      ? null
      : _formatMoneyValue(unitPrice, normalizedCurrencySymbol);
  final lineTotalText = unitPrice == null
      ? null
      : _formatMoneyValue(unitPrice * safeQuantity, normalizedCurrencySymbol);

  return <String, Object?>{
    ...?existing,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'rxRequired': rxRequired,
    'quantity': safeQuantity,
    'currencySymbol': normalizedCurrencySymbol,
    'badgeLabel': rxRequired ? 'Rx' : '',
    ...?unitPrice == null ? null : <String, Object?>{'unitPrice': unitPrice},
    ...?unitPriceText == null
        ? null
        : <String, Object?>{'unitPriceText': unitPriceText},
    ...?lineTotalText == null
        ? null
        : <String, Object?>{'lineTotalText': lineTotalText},
    'meta': _buildLineMeta(
      subtitle: subtitle,
      rxRequired: rxRequired,
      qty: safeQuantity,
    ),
  };
}

double? _readLineUnitPrice(Map data) {
  final raw = data['unitPrice'];
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim());
  return null;
}

String _readLineCurrencySymbol(Map data) {
  final raw = data['currencySymbol'];
  if (raw is String && raw.trim().isNotEmpty) {
    return raw.trim();
  }
  return r'$';
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
  final currencySymbol = lines.isNotEmpty
      ? _readLineCurrencySymbol(lines.first)
      : r'$';

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

String _formatMoneyValue(double amount, String currencySymbol) {
  return '$currencySymbol${amount.toStringAsFixed(2)}';
}

String _buildLineMeta({
  required String subtitle,
  required bool rxRequired,
  required int qty,
}) {
  final parts = <String>[];
  final s = subtitle.trim();
  if (s.isNotEmpty) parts.add(s);
  parts.add('Qty: $qty');
  if (rxRequired) parts.add('Rx');
  return parts.join(' • ');
}
