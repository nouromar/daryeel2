import 'package:flutter_daryeel_client_app/src/runtime/runtime_request_headers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mergeRuntimeRequestHeaders preserves auth headers', () {
    final headers = mergeRuntimeRequestHeaders(
      correlationHeaders: const <String, String>{
        'x-request-id': 'runtime-r1',
        'x-daryeel-session-id': 'runtime-s1',
      },
      requestHeadersProvider: () => const <String, String>{
        'Authorization': 'Bearer token-123',
        'x-request-id': 'app-r1',
      },
    );

    expect(headers['Authorization'], 'Bearer token-123');
    expect(headers['x-daryeel-session-id'], 'runtime-s1');
    expect(headers['x-request-id'], 'runtime-r1');
  });

  test('mergeRuntimeRequestHeaders tolerates provider failures', () {
    final headers = mergeRuntimeRequestHeaders(
      correlationHeaders: const <String, String>{
        'x-request-id': 'runtime-r1',
      },
      requestHeadersProvider: () => throw StateError('no auth yet'),
    );

    expect(headers, const <String, String>{'x-request-id': 'runtime-r1'});
  });
}
