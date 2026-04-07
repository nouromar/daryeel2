import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../../../routing/customer_schema_screen_route.dart';

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
        final prescriptionUploadIdRaw = store.getValue(
          'pharmacy.cart.prescriptionUploadId',
        );
        final attachedPrescriptionId = (prescriptionUploadIdRaw is String)
            ? prescriptionUploadIdRaw.trim()
            : '';
        final uploadsRaw = store.getValue('pharmacy.cart.prescriptionUploads');
        final uploadFilenames = _extractUploadFilenames(uploadsRaw);
        final hasUploads = uploadFilenames.isNotEmpty;
        final hasLegacyAttachment = attachedPrescriptionId.isNotEmpty;
        final hasPrescription = hasUploads || hasLegacyAttachment;

        final itemsByIdRaw = store.getValue('pharmacy.cart.itemsById');
        final itemsById = _coerceStringKeyedMap(itemsByIdRaw);

        final lines = <_CartLine>[];
        var hasRxItem = false;

        String? inferredCurrencySymbol;
        var totalPrice = 0.0;

        for (final entry in itemsById.entries) {
          final id = entry.key;
          final data = _coerceStringKeyedMap(entry.value);

          final quantityRaw = data['quantity'];
          final quantity = (quantityRaw is num)
              ? quantityRaw.toInt()
              : int.tryParse('${quantityRaw ?? ''}') ?? 0;
          if (quantity <= 0) continue;

          final title = (data['title'] is String)
              ? (data['title'] as String).trim()
              : '';
          final subtitle = (data['subtitle'] is String)
              ? (data['subtitle'] as String).trim()
              : '';

          final unitPrice = _tryParseMoney(subtitle);
          if (unitPrice != null) {
            totalPrice += unitPrice * quantity;
            inferredCurrencySymbol ??= _inferCurrencySymbol(subtitle);
          }

          final rxRequiredRaw = data['rxRequired'];
          final rxRequired =
              rxRequiredRaw == true ||
              (rxRequiredRaw is String &&
                  rxRequiredRaw.trim().toLowerCase() == 'true');
          if (rxRequired) hasRxItem = true;

          lines.add(
            _CartLine(
              id: id,
              title: title.isEmpty ? id : title,
              subtitle: subtitle,
              quantity: quantity,
              rxRequired: rxRequired,
            ),
          );
        }

        lines.sort((a, b) => a.title.compareTo(b.title));

        void clampTotalQuantity() {
          final raw = store.getValue('pharmacy.cart.totalQuantity');
          final current = (raw is num)
              ? raw.toInt()
              : int.tryParse('${raw ?? ''}') ?? 0;
          if (current < 0) {
            store.setValue('pharmacy.cart.totalQuantity', 0);
          }
        }

        void incrementLine(_CartLine line) {
          store.incrementValue(
            'pharmacy.cart.itemsById.${line.id}.quantity',
            1,
          );
          store.incrementValue('pharmacy.cart.totalQuantity', 1);
        }

        void decrementLine(_CartLine line) {
          if (line.quantity <= 1) {
            store.removeValue('pharmacy.cart.itemsById.${line.id}');
          } else {
            store.incrementValue(
              'pharmacy.cart.itemsById.${line.id}.quantity',
              -1,
            );
          }
          store.incrementValue('pharmacy.cart.totalQuantity', -1);
          clampTotalQuantity();
        }

        void clearCart() {
          store.removeValue('pharmacy.cart.itemsById');
          store.setValue('pharmacy.cart.totalQuantity', 0);
          store.removeValue('pharmacy.cart.prescriptionUploadId');
          store.removeValue('pharmacy.cart.prescriptionUploads');
        }

        if (lines.isEmpty && !hasPrescription) {
          return const InfoCardWidget(
            title: 'Cart is empty',
            subtitle: 'Add items from the pharmacy catalog.',
            surface: 'subtle',
          );
        }

        final showAttachPrescriptionLink = hasRxItem && !hasPrescription;
        final showAttachedPrescriptions = hasPrescription;
        final canCheckout = lines.isNotEmpty || hasPrescription;

        void goToPrescriptionUpload() {
          Navigator.of(context).pushNamed(
            CustomerSchemaScreenRoute.name,
            arguments: const <String, Object?>{
              'screenId': 'pharmacy_prescription_upload',
              'title': 'Attach Prescription',
              'chromePreset': 'pharmacy_cart_badge',
            },
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (lines.isNotEmpty)
              Card(
                elevation: switch (surface) {
                  'flat' => 0,
                  'subtle' => 0.5,
                  _ => 1.5,
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (final line in lines) ...[
                        _CartLineRow(
                          line: line,
                          onIncrement: () => incrementLine(line),
                          onDecrement: () => decrementLine(line),
                        ),
                        if (line != lines.last)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1),
                          ),
                      ],

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1),
                      ),

                      Row(
                        children: [
                          Text(
                            'Total',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          Text(
                            _formatMoney(totalPrice, inferredCurrencySymbol),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            if (showAttachedPrescriptions) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: goToPrescriptionUpload,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasUploads)
                        for (final filename in uploadFilenames)
                          Text(
                            filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                      else
                        const Text('Prescription attached'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showAttachPrescriptionLink) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: goToPrescriptionUpload,
                  child: const Text('Attach Prescription'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (canCheckout) ...[
              PrimaryActionBarWidget(
                primaryLabel: 'Checkout',
                expand: true,
                onPrimaryPressed: () {
                  Navigator.of(context).pushNamed(
                    'customer.schema_screen',
                    arguments: const <String, Object?>{
                      'screenId': 'pharmacy_checkout',
                      'title': 'Checkout',
                    },
                  );
                },
              ),
            ],

            if (lines.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: clearCart,
                    child: const Text('Clear cart'),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

final class _CartLine {
  const _CartLine({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.quantity,
    required this.rxRequired,
  });

  final String id;
  final String title;
  final String subtitle;
  final int quantity;
  final bool rxRequired;
}

List<String> _extractUploadFilenames(Object? uploadsRaw) {
  if (uploadsRaw is! List) return const <String>[];

  final filenames = <String>[];
  for (final entry in uploadsRaw) {
    if (entry is String) {
      final trimmed = entry.trim();
      if (trimmed.isNotEmpty) filenames.add(trimmed);
      continue;
    }

    if (entry is Map) {
      final filenameRaw = entry['filename'];
      if (filenameRaw is String) {
        final trimmed = filenameRaw.trim();
        if (trimmed.isNotEmpty) filenames.add(trimmed);
      }
    }
  }

  return filenames;
}

final class _CartLineRow extends StatelessWidget {
  const _CartLineRow({
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
  });

  final _CartLine line;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[];
    if (line.subtitle.trim().isNotEmpty) metaParts.add(line.subtitle.trim());
    metaParts.add('Qty: ${line.quantity}');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    metaParts.join(' • '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (line.rxRequired)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Text(
                          'Rx',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _CompactStepper(
          quantity: line.quantity,
          onIncrement: onIncrement,
          onDecrement: onDecrement,
        ),
      ],
    );
  }
}

final class _CompactStepper extends StatelessWidget {
  const _CompactStepper({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    const buttonConstraints = BoxConstraints.tightFor(width: 36, height: 36);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Decrease quantity',
          constraints: buttonConstraints,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onDecrement,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        IconButton(
          tooltip: 'Increase quantity',
          constraints: buttonConstraints,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onIncrement,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

Map<String, Object?> _coerceStringKeyedMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) continue;
      out[entry.key as String] = entry.value;
    }
    return out;
  }
  return const <String, Object?>{};
}

double? _tryParseMoney(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  final match = RegExp(r'(-?\d+(?:\.\d+)?)').firstMatch(value);
  if (match == null) return null;
  return double.tryParse(match.group(1) ?? '');
}

String? _inferCurrencySymbol(String raw) {
  final value = raw.trim();
  if (value.contains('\$')) return r'$';
  if (value.contains('€')) return '€';
  if (value.contains('£')) return '£';
  return null;
}

String _formatMoney(double amount, String? currencySymbol) {
  final fixed = amount.toStringAsFixed(2);
  if (currencySymbol == null || currencySymbol.isEmpty) return fixed;
  return '$currencySymbol$fixed';
}
