import 'package:flutter/material.dart';

import 'customer_auth_store.dart';
import 'customer_otp_login_screen.dart';

/// Customer-app root gate: unauthenticated users only see OTP login.
class CustomerAuthGate extends StatefulWidget {
  const CustomerAuthGate({
    required this.authStore,
    required this.apiBaseUrl,
    required this.authenticatedApp,
    super.key,
  });

  final CustomerAuthStore authStore;

  final String apiBaseUrl;

  /// App subtree to show once authenticated.
  final Widget authenticatedApp;

  @override
  State<CustomerAuthGate> createState() => _CustomerAuthGateState();
}

class _CustomerAuthGateState extends State<CustomerAuthGate> {
  late final Future<void> _initFuture = widget.authStore.initialize();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return ValueListenableBuilder<CustomerAuthState>(
          valueListenable: widget.authStore.state,
          builder: (context, state, _) {
            if (!state.isInitialized) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                home: const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            if (!state.isAuthenticated) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                home: CustomerOtpLoginScreen(
                  apiBaseUrl: widget.apiBaseUrl,
                  onVerified: widget.authStore.setAccessToken,
                ),
              );
            }

            return widget.authenticatedApp;
          },
        );
      },
    );
  }
}
