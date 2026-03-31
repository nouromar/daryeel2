import 'package:customer_app/src/app/customer_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders bundled customer schema by default', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const CustomerApp(schemaBaseUrl: ''));
    await tester.pumpAndSettle();

    expect(find.text('Daryeel2'), findsOneWidget);
    expect(find.text('Bundled customer home fallback'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Resolved from fragment'), findsOneWidget);
    expect(find.text('Open schema service'), findsOneWidget);
  });
}
