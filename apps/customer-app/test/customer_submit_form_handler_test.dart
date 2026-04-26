import 'package:customer_app/src/actions/customer_submit_form_handler.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'buildPharmacyServiceRequest builds common fields and pharmacy payload',
    () {
      final store = SchemaStateStore(
        initial: <String, Object?>{
          'pharmacy.cart.deliveryAddress': <String, Object?>{
            'text': 'Hodan, Mogadishu',
            'lat': 2.046934,
            'lng': 45.318162,
            'accuracy_m': 15,
          },
          'pharmacy.checkout.notes': 'Leave at reception',
          'pharmacy.checkout.payment.method': 'cash',
          'pharmacy.checkout.payment.timing': 'after_delivery',
          'pharmacy.cart.lines': <Object?>[
            <String, Object?>{
              'id': 'prod_paracetamol_500mg',
              'name': 'Paracetamol 500 mg',
              'subtitle': r'$1.00',
              'price': 1.0,
              'icon': 'pharmacy',
              'route': '',
              'rx_required': false,
              'quantity': 2,
            },
          ],
          'pharmacy.cart.summary.lines': <Object?>[
            <String, Object?>{
              'id': 'subtotal',
              'label': 'Subtotal',
              'amount': 2,
              'amountText': r'$2.00',
            },
          ],
          'pharmacy.cart.summary.total': <String, Object?>{
            'label': 'Total',
            'amount': 2,
            'amountText': r'$2.00',
          },
          'pharmacy.cart.prescriptionUploads': <Object?>[
            <String, Object?>{'id': 'rx-1', 'filename': 'rx1.jpg'},
          ],
        },
      );

      final request = CustomerSubmitFormHandler.buildPharmacyServiceRequest(
        store,
      );

      expect(request['service_id'], 'pharmacy');
      expect(request['delivery_location'], <String, Object?>{
        'text': 'Hodan, Mogadishu',
        'lat': 2.046934,
        'lng': 45.318162,
        'accuracy_m': 15,
      });
      expect(request['notes'], 'Leave at reception');
      expect(request['payment'], <String, Object?>{
        'method': 'cash',
        'timing': 'after_delivery',
      });

      final payload = request['order'] as Map<String, Object?>;
      expect(payload['items'], <Map<String, Object?>>[
        <String, Object?>{
          'productId': 'prod_paracetamol_500mg',
          'quantity': 2,
        },
      ]);
      expect(payload['prescriptionAttachmentIds'], <String>['rx-1']);
    },
  );
}
