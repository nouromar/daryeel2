import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

final class PharmacyCheckoutWidget extends StatelessWidget {
  const PharmacyCheckoutWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SchemaStateScope.maybeOf(context);
    if (store == null) {
      return const InfoCardWidget(
        title: 'Checkout unavailable',
        subtitle: 'Missing state store.',
        surface: 'subtle',
      );
    }

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final totalQuantityRaw = store.getValue('pharmacy.cart.totalQuantity');
        final totalQuantity = (totalQuantityRaw is num)
            ? totalQuantityRaw.toInt()
            : int.tryParse('${totalQuantityRaw ?? ''}') ?? 0;

        final uploadsRaw = store.getValue('pharmacy.cart.prescriptionUploads');
        final uploadsCount = (uploadsRaw is List)
            ? uploadsRaw.whereType<Map>().length
            : 0;
        final hasPrescription = uploadsCount > 0;

        final deliveryAddressRaw = store.getValue(
          'pharmacy.cart.deliveryAddress',
        );
        final deliveryAddress = (deliveryAddressRaw is Map)
            ? deliveryAddressRaw
                  .map((k, v) => MapEntry(k.toString(), v))
                  .cast<String, Object?>()
            : null;
        final addressText = (deliveryAddress?['text'] is String)
            ? (deliveryAddress?['text'] as String).trim()
            : '';

        final formStore = SchemaFormScope.maybeOf(context);
        final submittingListenable = (formStore == null)
            ? null
            : formStore.watchSubmitting('pharmacy_checkout');

        Widget buildSummary({required bool submitting}) {
          final subtitleParts = <String>[];
          if (addressText.isNotEmpty) {
            subtitleParts.add('Deliver to: $addressText');
          }
          subtitleParts.add('Items: $totalQuantity');
          if (hasPrescription) {
            subtitleParts.add('Prescriptions attached: $uploadsCount');
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoCardWidget(
                title: 'Checkout',
                subtitle: subtitleParts.join('\n'),
                surface: 'subtle',
              ),
              if (submitting) ...[
                const SizedBox(height: 12),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ],
            ],
          );
        }

        if (submittingListenable == null) {
          return buildSummary(submitting: false);
        }

        return ValueListenableBuilder<bool>(
          valueListenable: submittingListenable,
          builder: (context, submitting, child) =>
              buildSummary(submitting: submitting),
        );
      },
    );
  }
}
