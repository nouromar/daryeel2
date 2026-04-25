import 'package:customer_app/src/app/customer_app.dart';
import 'package:customer_app/src/schema/fallback_fragment_documents.dart';
import 'package:customer_app/src/schema/fallback_schema_bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('fallback customer_home bundle matches current schema', () {
    final doc = fallbackCustomerHomeBundle.document;

    expect(doc['id'], 'customer_home');
    expect(doc['documentType'], 'screen');
    expect(doc['product'], 'customer_app');
    expect(doc['themeId'], 'customer-default');
    expect(doc['themeMode'], 'light');

    final root = doc['root'] as Map<String, Object?>;
    expect(root['type'], 'BottomTabs');

    final slots = root['slots'] as Map<String, Object?>;
    final home = (slots['home'] as List).single as Map<String, Object?>;
    expect(home['type'], 'ScreenTemplate');

    final homeProps = home['props'] as Map<String, Object?>;
    expect(homeProps['headerGap'], 8);
    expect(homeProps['bodyPadding'], <String, Object?>{'all': 16});
    expect(homeProps['primaryScrollPadding'], <String, Object?>{
      'horizontal': 16,
    });
    expect(homeProps['footerPadding'], <String, Object?>{
      'left': 16,
      'top': 0,
      'right': 16,
      'bottom': 16,
    });

    final homeSlots = home['slots'] as Map<String, Object?>;
    final body = homeSlots['body'] as List;
    expect(body.length, 1);
    expect(body[0], <String, Object?>{
      'ref': 'fragment:customer_home_services_capsules_v1',
    });

    expect(
      fallbackFragmentDocuments.containsKey(
        'fragment:customer_home_services_capsules_v1',
      ),
      isTrue,
    );
  });

  testWidgets('renders bundled customer schema by default', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'customer_auth.access_token': 'token-1',
    });
    await tester.pumpWidget(const CustomerApp(schemaBaseUrl: ''));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Activities'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
  });
}
