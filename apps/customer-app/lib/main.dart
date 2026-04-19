import 'package:customer_app/src/app/customer_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _isLocalDevUrl(String url) {
  final u = url.trim().toLowerCase();
  return u.contains('localhost') || u.contains('127.0.0.1');
}

String _withLocalDefaultIfUnset(String value, String fallback) {
  final trimmed = value.trim();
  if (trimmed.isNotEmpty) return trimmed;
  if (kReleaseMode) return trimmed;
  return fallback;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const schemaBaseUrlEnv = String.fromEnvironment('SCHEMA_BASE_URL');
  const configBaseUrlEnv = String.fromEnvironment('CONFIG_BASE_URL');
  const apiBaseUrlEnv = String.fromEnvironment('API_BASE_URL');

  final schemaBaseUrl = _withLocalDefaultIfUnset(
    schemaBaseUrlEnv,
    'http://localhost:8011',
  );
  final configBaseUrl = _withLocalDefaultIfUnset(
    configBaseUrlEnv,
    'http://localhost:8011',
  );
  final apiBaseUrl = _withLocalDefaultIfUnset(
    apiBaseUrlEnv,
    'http://localhost:8010',
  );

  if (_isLocalDevUrl(schemaBaseUrl)) {
    final prefs = await SharedPreferences.getInstance();
    for (final screenId in const <String>[
      'customer_home',
      'customer_request_detail',
      'pharmacy_shop',
      'pharmacy_cart',
      'pharmacy_checkout',
      'pharmacy_prescription_upload',
    ]) {
      await prefs.remove('schema.pinned_doc_id.customer_app.$screenId');
    }

    await prefs.remove('daryeel_client.lkg_config_snapshot_json.customer_app');
  }

  runApp(
    CustomerApp(
      schemaBaseUrl: schemaBaseUrl,
      configBaseUrl: configBaseUrl,
      apiBaseUrl: apiBaseUrl,
    ),
  );
}
