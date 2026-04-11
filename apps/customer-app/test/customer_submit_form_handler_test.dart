import 'package:customer_app/src/actions/customer_submit_form_handler.dart';
import 'package:customer_app/src/schema/customer_schema_compatibility.dart';
import 'package:customer_app/src/schema/fallback_fragment_documents.dart';
import 'package:customer_app/src/schema/fallback_schema_bundle.dart';
import 'package:customer_app/src/ui/customer_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/app/runtime_session_scope.dart';
// ignore: implementation_imports
import 'package:flutter_daryeel_client_app/src/runtime/daryeel_runtime_session.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
            <String, Object?>{'id': 'prod_paracetamol_500mg', 'quantity': 2},
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

      final payload = request['payload'] as Map<String, Object?>;
      expect(payload['cart_lines'], <Map<String, Object?>>[
        <String, Object?>{
          'product_id': 'prod_paracetamol_500mg',
          'quantity': 2,
        },
      ]);
      expect(payload['summary_lines'], <Map<String, Object?>>[
        <String, Object?>{
          'id': 'subtotal',
          'label': 'Subtotal',
          'amount': 2,
          'amountText': r'$2.00',
        },
      ]);
      expect(payload['summary_total'], <String, Object?>{
        'label': 'Total',
        'amount': 2,
        'amountText': r'$2.00',
      });
      expect(payload['prescription_upload_ids'], <String>['rx-1']);
    },
  );

  testWidgets('submit defers checkout cleanup until after the current frame', (
    tester,
  ) async {
    final handler = CustomerSubmitFormHandler(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'http://localhost:8010/v1/pharmacy/orders',
        );
        return http.Response('{"ok": true}', 201);
      }),
    );
    addTearDown(handler.dispose);

    final session = _buildTestSession();
    addTearDown(session.dispose);

    final store = SchemaStateStore(
      initial: <String, Object?>{
        'pharmacy.cart.deliveryAddress': <String, Object?>{
          'text': 'Hodan, Mogadishu',
        },
        'pharmacy.checkout.notes': 'Leave at reception',
        'pharmacy.checkout.payment.method': 'cash',
        'pharmacy.checkout.payment.timing': 'after_delivery',
        'pharmacy.cart.lines': <Object?>[
          <String, Object?>{'id': 'prod_paracetamol_500mg', 'quantity': 2},
        ],
        'pharmacy.cart.totalQuantity': 2,
        'pharmacy.cart.hasRxItem': true,
        'pharmacy.cart.prescriptionUploads': <Object?>[
          <String, Object?>{'id': 'rx-1', 'filename': 'rx1.jpg'},
        ],
        'pharmacy.checkout': <String, Object?>{'notes': 'Leave at reception'},
      },
    );

    late BuildContext checkoutContext;

    await tester.pumpWidget(
      RuntimeSessionScope(
        session: session,
        child: SchemaStateScope(
          store: store,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) {
                              checkoutContext = context;
                              return const Scaffold(
                                body: Center(child: Text('Checkout route')),
                              );
                            },
                          ),
                        );
                      },
                      child: const Text('Open checkout'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Checkout route'), findsOneWidget);

    final response = await handler.submit(
      checkoutContext,
      const SubmitFormRequest(formId: 'pharmacy_checkout', values: {}),
    );

    expect(response.ok, isTrue);
    expect(
      store.getValue('pharmacy.cart.lines'),
      isA<List>().having(
        (value) => value.length,
        'length before post-frame cleanup',
        1,
      ),
    );
    expect(store.getValue('pharmacy.cart.totalQuantity'), 2);
    expect(find.text('Checkout route'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(
      store.getValue('pharmacy.cart.lines'),
      isA<List>().having((value) => value.length, 'length', 0),
    );
    expect(store.getValue('pharmacy.cart.totalQuantity'), 0);
    expect(store.getValue('pharmacy.cart.hasRxItem'), isFalse);
    expect(store.getValue('pharmacy.cart.prescriptionUploads'), isNull);
    expect(store.getValue('pharmacy.checkout'), isNull);
    expect(find.text('Checkout route'), findsNothing);
    expect(find.text('Order submitted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

DaryeelRuntimeSession _buildTestSession() {
  return DaryeelRuntimeSession(
    appConfig: DaryeelClientAppConfig(
      runtime: DaryeelRuntimeConfig(
        appId: 'customer-app-test',
        product: 'customer_app',
        fallbackBundle: fallbackCustomerHomeBundle,
        fallbackFragmentDocuments: fallbackFragmentDocuments,
        resolveLocalTheme: resolveCustomerTheme,
        resolveThemeMode: resolveThemeMode,
        defaultThemeId: 'customer-default',
        defaultThemeMode: 'light',
        buildCompatibilityChecker: (overlay) =>
            CustomerSchemaCompatibilityChecker(overlay: overlay),
      ),
      appBarTitle: 'Test',
      buildRegistry:
          ({
            required ScreenSchema screen,
            required SchemaActionDispatcher actionDispatcher,
            required SchemaVisibilityContext visibility,
            RuntimeDiagnostics? diagnostics,
            Map<String, Object?> diagnosticsContext = const <String, Object?>{},
          }) {
            return SchemaWidgetRegistry();
          },
    ),
    schemaBaseUrl: 'http://localhost:8011',
    configBaseUrl: 'http://localhost:8011',
    apiBaseUrl: 'http://localhost:8010',
    diagnosticsBufferMaxEvents: 20,
  );
}
