import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

/// App-level action dispatcher that adds customer-app specific action types.
///
/// We keep this in the app so we can add higher-level behaviors (like cart
/// list upserts) without changing the shared runtime in `packages/*`.
final class CustomerActionDispatcher extends SchemaActionDispatcher {
  const CustomerActionDispatcher({required this.delegate});

  final SchemaActionDispatcher delegate;

  static const String pharmacyCartUpsert = 'pharmacy_cart_upsert';
  static const String pharmacyCartIncrement = 'pharmacy_cart_increment';
  static const String pharmacyCartDecrement = 'pharmacy_cart_decrement';
  static const String pharmacyCartClear = 'pharmacy_cart_clear';

  @override
  Future<void> dispatch(BuildContext context, ActionDefinition action) async {
    switch (action.type) {
      case pharmacyCartUpsert:
        _migrateLegacyCartStateIfNeeded(context);
        _pharmacyCartUpsert(context, action);
        return;
      case pharmacyCartIncrement:
        _migrateLegacyCartStateIfNeeded(context);
        _pharmacyCartChangeQuantity(context, action, delta: 1);
        return;
      case pharmacyCartDecrement:
        _migrateLegacyCartStateIfNeeded(context);
        _pharmacyCartChangeQuantity(context, action, delta: -1);
        return;
      case pharmacyCartClear:
        _migrateLegacyCartStateIfNeeded(context);
        _pharmacyCartClear(context);
        return;
      default:
        return delegate.dispatch(context, action);
    }
  }
}

/// Migrates older persisted cart state (`itemsById`) into the current list-based
/// shape (`lines`). Safe to call repeatedly.
void migrateLegacyPharmacyCartState(SchemaStateStore store) {
  final linesRaw = store.getValue('pharmacy.cart.lines');
  final hasLines = linesRaw is List && linesRaw.isNotEmpty;
  if (hasLines) return;

  final legacyRaw = store.getValue('pharmacy.cart.itemsById');
  if (legacyRaw is! Map) return;

  final nextLines = <Map<String, Object?>>[];
  var total = 0;

  for (final entry in legacyRaw.entries) {
    final id = entry.key?.toString().trim() ?? '';
    if (id.isEmpty) continue;
    final data = entry.value;
    if (data is! Map) continue;

    final quantityRaw = data['quantity'];
    final quantity = (quantityRaw is num)
        ? quantityRaw.toInt()
        : int.tryParse('${quantityRaw ?? ''}') ?? 0;
    if (quantity <= 0) continue;

    final title = (data['title'] is String)
        ? (data['title'] as String).trim()
        : id;
    final subtitle = (data['subtitle'] is String)
        ? (data['subtitle'] as String).trim()
        : '';
    final rxRaw = data['rxRequired'];
    final rxRequired =
        rxRaw == true ||
        (rxRaw is String && rxRaw.trim().toLowerCase() == 'true');

    nextLines.add(<String, Object?>{
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'rxRequired': rxRequired,
      'quantity': quantity,
      'meta': _buildLineMeta(
        subtitle: subtitle,
        rxRequired: rxRequired,
        qty: quantity,
      ),
    });

    total += quantity;
  }

  if (nextLines.isEmpty) return;
  store.setValue('pharmacy.cart.lines', nextLines);
  store.setValue('pharmacy.cart.totalQuantity', total);
  store.removeValue('pharmacy.cart.itemsById');
  _recomputeHasRxItem(store, lines: nextLines);
}

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

  final id = readInterpolatedString('id');
  if (id == null) return;

  final title = readInterpolatedString('title') ?? id;
  final subtitle = readInterpolatedString('subtitle') ?? '';
  final rxRequired = readInterpolatedBool('rxRequired', fallback: false);

  double? readInterpolatedDouble(String key) {
    final v = raw[key];
    if (v is num) return v.toDouble();
    if (v is String) {
      final resolved = interpolateSchemaString(v, context).trim();
      return double.tryParse(resolved);
    }
    return null;
  }

  final unitPrice = readInterpolatedDouble('unitPrice');
  final unitPriceEntry = (unitPrice == null)
      ? null
      : <String, Object?>{'unitPrice': unitPrice};

  final nextLines = _ensureCartLines(store);

  final idx = nextLines.indexWhere((e) => (e['id'] ?? '').toString() == id);
  if (idx == -1) {
    nextLines.add(<String, Object?>{
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'rxRequired': rxRequired,
      ...?unitPriceEntry,
      'quantity': 1,
      // Precomputed meta to avoid per-item conditional logic in schemas.
      'meta': _buildLineMeta(
        subtitle: subtitle,
        rxRequired: rxRequired,
        qty: 1,
      ),
    });
  } else {
    final current = nextLines[idx];
    final qRaw = current['quantity'];
    final q = (qRaw is num) ? qRaw.toInt() : int.tryParse('$qRaw') ?? 0;
    final nextQ = q + 1;
    nextLines[idx] = <String, Object?>{
      ...current,
      'title': title,
      'subtitle': subtitle,
      'rxRequired': rxRequired,
      ...?unitPriceEntry,
      'quantity': nextQ,
      'meta': _buildLineMeta(
        subtitle: subtitle,
        rxRequired: rxRequired,
        qty: nextQ,
      ),
    };
  }

  store.setValue('pharmacy.cart.lines', nextLines);
  store.incrementValue('pharmacy.cart.totalQuantity', 1);
  _clampTotalQuantity(store);
  _recomputeHasRxItem(store, lines: nextLines);
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

    nextLines[idx] = <String, Object?>{
      ...current,
      'quantity': nextQ,
      'meta': _buildLineMeta(
        subtitle: subtitle,
        rxRequired: rxRequired,
        qty: nextQ,
      ),
    };
  }

  store.setValue('pharmacy.cart.lines', nextLines);
  store.incrementValue('pharmacy.cart.totalQuantity', delta);
  _clampTotalQuantity(store);
  _recomputeHasRxItem(store, lines: nextLines);
}

void _pharmacyCartClear(BuildContext context) {
  final store = SchemaStateScope.maybeOf(context);
  if (store == null) return;

  store.setValue('pharmacy.cart.lines', const <Object?>[]);
  store.setValue('pharmacy.cart.totalQuantity', 0);
  store.setValue('pharmacy.cart.hasRxItem', false);
  store.removeValue('pharmacy.cart.prescriptionUploadId');
  store.removeValue('pharmacy.cart.prescriptionUploads');
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

void _migrateLegacyCartStateIfNeeded(BuildContext context) {
  final store = SchemaStateScope.maybeOf(context);
  if (store == null) return;

  migrateLegacyPharmacyCartState(store);
}
