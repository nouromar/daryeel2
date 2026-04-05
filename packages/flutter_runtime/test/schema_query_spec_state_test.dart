import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(r'SchemaQuerySpec resolves $state bindings', () {
    final state = SchemaStateStore(initial: <String, Object?>{
      'q': 'abc',
      'limit': 10,
      'empty': '   ',
    });

    final params = SchemaQuerySpec.resolveParams(
      <String, Object?>{
        'q': r'$state.q',
        'limit': r'$state:limit',
        'shouldDropEmpty': r'$state.empty',
        'static': 'ok',
      },
      stateStore: state,
    );

    expect(params['q'], 'abc');
    expect(params['limit'], '10');
    expect(params.containsKey('shouldDropEmpty'), isFalse);
    expect(params['static'], 'ok');
  });
}
