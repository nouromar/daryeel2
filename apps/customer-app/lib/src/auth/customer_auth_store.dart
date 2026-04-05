import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class CustomerAuthState {
  const CustomerAuthState._({required this.isInitialized, this.accessToken});

  const CustomerAuthState.uninitialized() : this._(isInitialized: false);

  const CustomerAuthState.unauthenticated()
    : this._(isInitialized: true, accessToken: null);

  const CustomerAuthState.authenticated({required String accessToken})
    : this._(isInitialized: true, accessToken: accessToken);

  final bool isInitialized;
  final String? accessToken;

  bool get isAuthenticated => (accessToken != null && accessToken!.isNotEmpty);
}

/// Minimal local auth store for customer-app.
///
/// Scope: app gating only ("show OTP login" vs "show runtime shell").
///
/// This does not perform OTP verification by itself; the OTP screen should call
/// [setAccessToken] when verification succeeds.
final class CustomerAuthStore {
  CustomerAuthStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const String _tokenKey = 'customer_auth.access_token';

  SharedPreferences? _prefs;
  final ValueNotifier<CustomerAuthState> state =
      ValueNotifier<CustomerAuthState>(const CustomerAuthState.uninitialized());

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();

    final token = _prefs!.getString(_tokenKey);
    if (token != null && token.trim().isNotEmpty) {
      state.value = CustomerAuthState.authenticated(accessToken: token.trim());
    } else {
      state.value = const CustomerAuthState.unauthenticated();
    }
  }

  Future<void> setAccessToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await clear();
      return;
    }

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_tokenKey, trimmed);
    state.value = CustomerAuthState.authenticated(accessToken: trimmed);
  }

  Future<void> clear() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_tokenKey);
    state.value = const CustomerAuthState.unauthenticated();
  }

  void dispose() {
    state.dispose();
  }
}
