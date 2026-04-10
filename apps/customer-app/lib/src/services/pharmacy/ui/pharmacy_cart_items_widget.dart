import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../../../actions/customer_action_dispatcher.dart';
import '../../../routing/customer_schema_screen_route.dart';
import '../../ecommerce/ui/cart/ecommerce_cart_models.dart';
import '../../ecommerce/ui/cart/ecommerce_cart_widget.dart';

final class PharmacyCartItemsWidget extends StatelessWidget {
  const PharmacyCartItemsWidget({super.key, this.surface = 'raised'});

  final String surface;

  @override
  Widget build(BuildContext context) {
    final store = SchemaStateScope.maybeOf(context);
    if (store == null) {
      return UnknownSchemaWidget(
        componentName: 'PharmacyCartItems(missing-state-scope)',
      );
    }

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        migrateLegacyPharmacyCartState(store);

        final lines = _readLines(store);
        final hasPrescription = _hasPrescription(store);
        final hasRxItem = _readHasRxItem(store, lines: lines);
        final totals = _computeTotals(store, lines: lines);

        void openCheckout() {
          Navigator.of(context).pushNamed(
            CustomerSchemaScreenRoute.name,
            arguments: const <String, Object?>{
              'screenId': 'pharmacy_checkout',
              'title': 'Checkout',
            },
          );
        }

        void openPrescriptionUpload() {
          Navigator.of(context).pushNamed(
            CustomerSchemaScreenRoute.name,
            arguments: const <String, Object?>{
              'screenId': 'pharmacy_prescription_upload',
              'title': 'Attach Prescription',
              'chromePreset': 'pharmacy_cart_badge',
            },
          );
        }

        void setLines(List<Map<String, Object?>> nextLines) {
          store.setValue('pharmacy.cart.lines', nextLines);

          var totalQty = 0;
          for (final line in nextLines) {
            final qRaw = line['quantity'];
            final q = (qRaw is num) ? qRaw.toInt() : int.tryParse('$qRaw') ?? 0;
            if (q > 0) totalQty += q;
          }
          store.setValue('pharmacy.cart.totalQuantity', totalQty);

          store.setValue(
            'pharmacy.cart.hasRxItem',
            _computeHasRxItem(nextLines),
          );
        }

        void increment(String id) {
          final next = [...lines];
          final idx = next.indexWhere((e) => e.id == id);
          if (idx == -1) return;

          final current = next[idx];
          next[idx] = EcommerceCartLine(
            id: current.id,
            title: current.title,
            subtitle: current.subtitle,
            quantity: current.quantity + 1,
            rxRequired: current.rxRequired,
            unitPrice: current.unitPrice,
            currencySymbol: current.currencySymbol,
          );

          setLines(_serializeLines(next));
        }

        void decrement(String id) {
          final next = [...lines];
          final idx = next.indexWhere((e) => e.id == id);
          if (idx == -1) return;

          final current = next[idx];
          final nextQty = current.quantity - 1;
          if (nextQty <= 0) {
            next.removeAt(idx);
          } else {
            next[idx] = EcommerceCartLine(
              id: current.id,
              title: current.title,
              subtitle: current.subtitle,
              quantity: nextQty,
              rxRequired: current.rxRequired,
              unitPrice: current.unitPrice,
              currencySymbol: current.currencySymbol,
            );
          }

          setLines(_serializeLines(next));
        }

        void clearCart() {
          store.setValue('pharmacy.cart.lines', const <Object?>[]);
          store.setValue('pharmacy.cart.totalQuantity', 0);
          store.setValue('pharmacy.cart.hasRxItem', false);

          // Keep older persisted shapes tidy/consistent.
          store.removeValue('pharmacy.cart.itemsById');
          store.removeValue('pharmacy.cart.prescriptionUploads');
          store.removeValue('pharmacy.cart.prescriptionUploadId');
        }

        final prescriptionSection = _buildPrescriptionSection(
          context,
          store: store,
          showCta: hasRxItem,
          onOpen: openPrescriptionUpload,
          onRemoveUploadAt: (idx) => _removePrescriptionUploadAt(store, idx),
          onClearLegacyId: () =>
              store.setValue('pharmacy.cart.prescriptionUploadId', ''),
        );

        return SingleChildScrollView(
          child: EcommerceCartWidget(
            lines: lines,
            totals: totals,
            hasPrescription: hasPrescription,
            showPrescriptionCta: hasRxItem,
            surface: surface,
            emptyTitle: 'Cart is empty',
            emptySubtitle: 'Add items from the pharmacy catalog.',
            onIncrement: increment,
            onDecrement: decrement,
            onClear: clearCart,
            onCheckout: openCheckout,
            onAttachPrescription: openPrescriptionUpload,
            prescriptionSection: prescriptionSection,
          ),
        );
      },
    );
  }
}

List<EcommerceCartLine> _readLines(SchemaStateStore store) {
  final raw = store.getValue('pharmacy.cart.lines');
  if (raw is! List) return const <EcommerceCartLine>[];

  final out = <EcommerceCartLine>[];
  for (final entry in raw) {
    if (entry is! Map) continue;

    final id = (entry['id'] ?? '').toString().trim();
    if (id.isEmpty) continue;

    final title = (entry['title'] ?? id).toString().trim();
    final subtitle = (entry['subtitle'] ?? entry['meta'] ?? '')
        .toString()
        .trim();

    final qRaw = entry['quantity'];
    final quantity = (qRaw is num)
        ? qRaw.toInt()
        : int.tryParse('${qRaw ?? ''}') ?? 0;
    if (quantity <= 0) continue;

    final rxRaw = entry['rxRequired'];
    final rxRequired =
        rxRaw == true ||
        (rxRaw is String && rxRaw.trim().toLowerCase() == 'true');

    final unitPriceRaw = entry['unitPrice'];
    final unitPrice = (unitPriceRaw is num)
        ? unitPriceRaw.toDouble()
        : double.tryParse('${unitPriceRaw ?? ''}') ?? _tryParseMoney(subtitle);

    out.add(
      EcommerceCartLine(
        id: id,
        title: title.isEmpty ? id : title,
        subtitle: _stripMetaMarkers(subtitle),
        quantity: quantity,
        rxRequired: rxRequired,
        unitPrice: unitPrice,
        currencySymbol: _inferCurrencySymbol(subtitle) ?? r'$',
      ),
    );
  }

  out.sort((a, b) => a.title.compareTo(b.title));
  return out;
}

List<Map<String, Object?>> _serializeLines(List<EcommerceCartLine> lines) {
  return lines
      .map((line) {
        final unitPriceEntry = line.unitPrice == null
            ? null
            : <String, Object?>{'unitPrice': line.unitPrice};

        return <String, Object?>{
          'id': line.id,
          'title': line.title,
          'subtitle': line.subtitle,
          'quantity': line.quantity,
          'rxRequired': line.rxRequired,
          ...?unitPriceEntry,
        };
      })
      .toList(growable: false);
}

bool _readHasRxItem(
  SchemaStateStore store, {
  required List<EcommerceCartLine> lines,
}) {
  final raw = store.getValue('pharmacy.cart.hasRxItem');
  if (raw is bool) return raw;
  return lines.any((e) => e.rxRequired);
}

bool _computeHasRxItem(List<Map<String, Object?>> lines) {
  for (final line in lines) {
    final qRaw = line['quantity'];
    final q = (qRaw is num) ? qRaw.toInt() : int.tryParse('$qRaw') ?? 0;
    if (q <= 0) continue;

    final rxRaw = line['rxRequired'];
    final rx =
        rxRaw == true ||
        (rxRaw is String && rxRaw.trim().toLowerCase() == 'true');
    if (rx) return true;
  }
  return false;
}

EcommerceCartTotals _computeTotals(
  SchemaStateStore store, {
  required List<EcommerceCartLine> lines,
}) {
  var subtotal = 0.0;
  for (final line in lines) {
    final p = line.unitPrice;
    if (p == null) continue;
    subtotal += p * line.quantity;
  }

  final taxRaw = store.getValue('pharmacy.cart.tax');
  final discountRaw = store.getValue('pharmacy.cart.discount');
  final tax = (taxRaw is num) ? taxRaw.toDouble() : 0.0;
  final discount = (discountRaw is num) ? discountRaw.toDouble() : 0.0;

  return EcommerceCartTotals(subtotal: subtotal, tax: tax, discount: discount);
}

String _stripMetaMarkers(String subtitle) {
  var s = subtitle.trim();
  if (s.isEmpty) return s;

  s = s
      .replaceAll(RegExp(r'\bQty:\s*\d+\b'), '')
      .replaceAll(RegExp(r'\b(r|R)(x|X)\b'), '')
      .replaceAll(RegExp(r'\s*•\s*'), ' • ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  if (s == '•') return '';
  if (s.startsWith('• ')) s = s.substring(2).trim();
  if (s.endsWith(' •')) s = s.substring(0, s.length - 2).trim();
  return s;
}

double? _tryParseMoney(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final cleaned = trimmed.replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String? _inferCurrencySymbol(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final match = RegExp(r'^[^0-9\-\.]').firstMatch(trimmed);
  return match?.group(0);
}

Widget? _buildPrescriptionSection(
  BuildContext context, {
  required SchemaStateStore store,
  required bool showCta,
  required VoidCallback onOpen,
  required void Function(int index) onRemoveUploadAt,
  required VoidCallback onClearLegacyId,
}) {
  final uploadsRaw = store.getValue('pharmacy.cart.prescriptionUploads');
  final uploads = _extractUploadFilenames(uploadsRaw);

  final legacyIdRaw = store.getValue('pharmacy.cart.prescriptionUploadId');
  final legacyId = (legacyIdRaw is String) ? legacyIdRaw.trim() : '';

  final hasUploads = uploads.isNotEmpty;
  final hasLegacyId = legacyId.isNotEmpty;

  if (!showCta && !hasUploads && !hasLegacyId) return null;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showCta && !hasUploads && !hasLegacyId)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onOpen,
            child: const Text('Attach Prescription'),
          ),
        ),

      if (hasUploads) ...[
        ActionCardWidget(
          title: 'Prescription attached',
          subtitle: '',
          surface: 'flat',
          onTap: onOpen,
        ),
        const SizedBox(height: 8),
        ...uploads.asMap().entries.map((entry) {
          final idx = entry.key;
          final filename = entry.value;

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove prescription',
                  onPressed: () => onRemoveUploadAt(idx),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          );
        }),
      ],

      if (!hasUploads && hasLegacyId) ...[
        ActionCardWidget(
          title: 'Prescription attached',
          subtitle: '',
          surface: 'flat',
          onTap: onOpen,
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onClearLegacyId,
            child: const Text('Remove prescription'),
          ),
        ),
      ],
    ],
  );
}

List<String> _extractUploadFilenames(Object? raw) {
  if (raw is! List) return const <String>[];
  final out = <String>[];
  for (final e in raw) {
    if (e is Map) {
      final filename = e['filename'];
      if (filename is String && filename.trim().isNotEmpty) {
        out.add(filename.trim());
      }
    }
  }
  return out;
}

void _removePrescriptionUploadAt(SchemaStateStore store, int index) {
  final raw = store.getValue('pharmacy.cart.prescriptionUploads');
  if (raw is! List) return;
  if (index < 0 || index >= raw.length) return;

  final next = [...raw]..removeAt(index);
  store.setValue('pharmacy.cart.prescriptionUploads', next);
  if (next.isEmpty) {
    store.setValue('pharmacy.cart.prescriptionUploadId', '');
  }
}

bool _hasPrescription(SchemaStateStore store) {
  final uploadsRaw = store.getValue('pharmacy.cart.prescriptionUploads');
  if (uploadsRaw is List && uploadsRaw.isNotEmpty) return true;

  final legacyIdRaw = store.getValue('pharmacy.cart.prescriptionUploadId');
  return legacyIdRaw is String && legacyIdRaw.trim().isNotEmpty;
}
