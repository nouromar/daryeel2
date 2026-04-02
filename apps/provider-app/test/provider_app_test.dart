import 'package:flutter_test/flutter_test.dart';
import 'package:provider_app/src/app/provider_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders bundled provider schema by default', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const ProviderApp(schemaBaseUrl: ''));
    await tester.pumpAndSettle();

    expect(find.text('Daryeel2'), findsOneWidget);
    expect(find.text('Bundled provider home fallback'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Resolved from fragment'), findsOneWidget);
    expect(find.text('Open schema service'), findsOneWidget);
  });
}
