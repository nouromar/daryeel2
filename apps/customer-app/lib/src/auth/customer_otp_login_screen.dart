import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Minimal OTP login UI.
///
/// This screen is intentionally simple: the app should wire real OTP
/// verification and then call [onVerified] with an access token.
class CustomerOtpLoginScreen extends StatefulWidget {
  const CustomerOtpLoginScreen({
    required this.apiBaseUrl,
    required this.onVerified,
    super.key,
  });

  final String apiBaseUrl;

  final Future<void> Function(String accessToken) onVerified;

  @override
  State<CustomerOtpLoginScreen> createState() => _CustomerOtpLoginScreenState();
}

class _CustomerOtpLoginScreenState extends State<CustomerOtpLoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  final _phoneFocusNode = FocusNode();
  final _otpFocusNode = FocusNode();

  _OtpStage _stage = _OtpStage.enterPhone;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _phoneFocusNode.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  String _normalizedApiBaseUrl() {
    final base = widget.apiBaseUrl.trim();
    if (base.isEmpty) {
      throw StateError('API base URL is not configured');
    }
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  Future<void> _sendCode() async {
    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      final phone = _phoneController.text.trim();
      if (phone.isEmpty) {
        throw StateError('Enter phone number');
      }

      final normalized = _normalizedApiBaseUrl();
      final uri = Uri.parse('$normalized/dev/auth/otp/start');
      final response = await http.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{'phone': phone}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Send code failed (HTTP ${response.statusCode})');
      }

      setState(() {
        _stage = _OtpStage.enterCode;
      });

      _otpFocusNode.requestFocus();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      final phone = _phoneController.text.trim();
      final otp = _otpController.text.trim();

      if (phone.isEmpty) {
        throw StateError('Enter phone number');
      }
      if (otp.isEmpty) {
        throw StateError('Enter OTP');
      }

      final normalized = _normalizedApiBaseUrl();
      final uri = Uri.parse('$normalized/dev/auth/otp/verify');

      final response = await http.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{'phone': phone, 'otp': otp}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Login failed (HTTP ${response.statusCode})');
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const FormatException('Login response was not an object');
      }

      final accessToken = decoded['accessToken'];
      if (accessToken is! String || accessToken.trim().isEmpty) {
        throw const FormatException('Login response missing accessToken');
      }

      await widget.onVerified(accessToken.trim());
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _stage == _OtpStage.enterPhone
                    ? 'Enter your phone number'
                    : 'Enter the code we sent you',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('otp_login.phone'),
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                enabled: !_submitting && _stage == _OtpStage.enterPhone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  hintText: '+252...',
                ),
              ),
              const SizedBox(height: 12),
              if (_stage == _OtpStage.enterCode) ...[
                TextField(
                  key: const Key('otp_login.otp'),
                  controller: _otpController,
                  focusNode: _otpFocusNode,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(labelText: 'Code'),
                ),
                const SizedBox(height: 16),
              ] else ...[
                const SizedBox(height: 16),
              ],
              if (_error != null) ...[
                Text(
                  _error!,
                  key: const Key('otp_login.error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              if (_stage == _OtpStage.enterPhone)
                FilledButton(
                  key: const Key('otp_login.send'),
                  onPressed: _submitting ? null : _sendCode,
                  child: Text(_submitting ? 'Sending…' : 'Send code'),
                )
              else
                FilledButton(
                  key: const Key('otp_login.submit'),
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting ? 'Verifying…' : 'Verify'),
                ),
              if (kDebugMode) ...[
                const SizedBox(height: 12),
                Text(
                  'Dev note: OTP uses /dev/auth/otp/verify and accepts any 6 digits (until SMS integration).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _OtpStage { enterPhone, enterCode }
