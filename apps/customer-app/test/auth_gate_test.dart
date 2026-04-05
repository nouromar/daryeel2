import 'package:customer_app/src/app/customer_app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Unauthenticated shows OTP login screen', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const CustomerApp());

    // Wait for auth store init.
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('otp_login.phone')), findsOneWidget);
    expect(find.byKey(const Key('otp_login.send')), findsOneWidget);
  });

  testWidgets('Authenticated shows runtime shell', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'customer_auth.access_token': 'token-1',
    });

    await tester.pumpWidget(const CustomerApp());

    // Wait for auth store init + shell to finish its initial FutureBuilder.
    await tester.pumpAndSettle();

    // The shell app bar title should appear when the schema runtime is shown.
    expect(find.text('Daryeel2 Customer'), findsOneWidget);
  });
}
