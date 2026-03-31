import 'dart:convert';

import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:http/http.dart' as http;

class HttpRemoteDiagnosticsTransport extends RemoteDiagnosticsTransport {
  HttpRemoteDiagnosticsTransport({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<void> send({
    required Uri endpoint,
    required Map<String, Object?> body,
    Map<String, String>? headers,
  }) async {
    final mergedHeaders = <String, String>{
      'content-type': 'application/json',
      if (headers != null) ...headers,
    };

    final response = await _client.post(
      endpoint,
      headers: mergedHeaders,
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Diagnostics endpoint returned ${response.statusCode}');
    }
  }
}
