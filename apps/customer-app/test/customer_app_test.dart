import 'package:customer_app/src/app/customer_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders bundled customer schema by default', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'customer_auth.access_token': 'token-1',
    });
    await tester.pumpWidget(const CustomerApp(schemaBaseUrl: ''));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Activities'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Resolved from fragment'), findsOneWidget);

    expect(find.text('Ambulance'), findsOneWidget);
    expect(find.text('Home Visit'), findsOneWidget);
    expect(find.text('Pharmacy'), findsOneWidget);

    await tester.tap(find.text('Ambulance'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Schema base URL is not configured'),
      findsOneWidget,
    );
  });
}
