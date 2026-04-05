import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SchemaFormStore stores bounded JSON-like map values', () {
    final store = SchemaFormStore(
      maxJsonDepth: 4,
      maxJsonNodes: 100,
      maxJsonEntriesPerMap: 20,
      maxJsonItemsPerList: 20,
      maxJsonKeyLength: 20,
    );

    store.setFieldValue(
      'checkout',
      'delivery_location',
      <String, Object?>{
        'text': 'Hodan, Mogadishu',
        'lat': 2.046934,
        'lng': 45.318162,
        'place_id': 'abc',
        'meta': <String, Object?>{
          'accuracy_m': 15,
        },
      },
    );

    final v = store.getFieldValue('checkout', 'delivery_location');
    expect(v, isA<Map<String, Object?>>());

    final map = v! as Map<String, Object?>;
    expect(map['text'], 'Hodan, Mogadishu');
    expect(map['lat'], 2.046934);
    expect(map['meta'], isA<Map<String, Object?>>());
    expect((map['meta'] as Map<String, Object?>)['accuracy_m'], 15);
  });

  test('SchemaFormStore truncates overly large lists/maps', () {
    final store = SchemaFormStore(
      maxJsonDepth: 3,
      maxJsonNodes: 50,
      maxJsonEntriesPerMap: 3,
      maxJsonItemsPerList: 2,
    );

    store.setFieldValue(
      'f',
      'v',
      <String, Object?>{
        'a': [1, 2, 3, 4],
        'b': true,
        'c': 'ok',
        'd': 'drop',
        'e': 'drop2',
      },
    );

    final v = store.getFieldValue('f', 'v') as Map<String, Object?>;
    // Only 3 entries allowed.
    expect(v.length, 3);

    final a = v['a'];
    expect(a, isA<List<Object?>>());
    expect((a as List).length, 2);
  });

  test('SchemaFormStore ignores non-string map keys', () {
    final store = SchemaFormStore(maxJsonEntriesPerMap: 20);

    store.setFieldValue(
      'f',
      'v',
      <Object?, Object?>{
        1: 'no',
        'ok': 'yes',
        true: 'no',
      },
    );

    final v = store.getFieldValue('f', 'v') as Map<String, Object?>;
    expect(v.keys, contains('ok'));
    expect(v.keys, isNot(contains('1')));
  });
}
