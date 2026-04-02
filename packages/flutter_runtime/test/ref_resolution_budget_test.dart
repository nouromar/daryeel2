import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFragmentLoader implements FragmentDocumentLoader {
  _FakeFragmentLoader(this.docs);

  final Map<String, Map<String, Object?>> docs;

  @override
  Future<Map<String, Object?>> loadFragmentDocument(String fragmentId) async {
    final doc = docs[fragmentId];
    if (doc == null) {
      throw StateError('Missing fragment: $fragmentId');
    }
    return doc;
  }
}

Map<String, Object?> _fragmentDoc(String id) {
  return <String, Object?>{
    'schemaVersion': '1.0',
    'id': id,
    'documentType': 'fragment',
    'node': <String, Object?>{
      'type': 'InfoCard',
      'props': const <String, Object?>{
        'title': 'X',
      },
    },
  };
}

Map<String, Object?> _refFragmentDoc(String id, String ref) {
  return <String, Object?>{
    'schemaVersion': '1.0',
    'id': id,
    'documentType': 'fragment',
    'node': <String, Object?>{
      'type': 'ScreenTemplate',
      'slots': <String, Object?>{
        'body': <Object?>[
          <String, Object?>{'ref': ref},
        ],
      },
    },
  };
}

void main() {
  test('resolveScreenRefs enforces maxFragments budget', () async {
    final refs = List<String>.generate(6, (i) => 'section:frag_$i');

    final docs = <String, Map<String, Object?>>{
      for (final ref in refs) ref: _fragmentDoc(ref),
    };

    final schema = ScreenSchema(
      schemaVersion: '1.0',
      id: 'budget_test',
      documentType: 'screen',
      product: 'customer_app',
      service: null,
      themeId: 'customer-default',
      themeMode: 'light',
      root: ComponentNode(
        type: 'ScreenTemplate',
        props: const <String, Object?>{},
        slots: <String, List<SchemaNode>>{
          'body': [for (final ref in refs) RefNode(ref: ref)],
        },
        actions: const <String, String>{},
        bind: null,
        visibleWhen: null,
      ),
      actions: const <String, ActionDefinition>{},
    );

    final result = await resolveScreenRefs(
      schema: schema,
      loader: _FakeFragmentLoader(docs),
      maxFragments: 3,
    );

    expect(
      result.errors.any((e) => e.message == 'Exceeded maxFragments=3'),
      isTrue,
    );
  });

  test('resolveScreenRefs reports circular refs', () async {
    const a = 'section:a';
    const b = 'section:b';

    final docs = <String, Map<String, Object?>>{
      a: _refFragmentDoc(a, b),
      b: _refFragmentDoc(b, a),
    };

    final schema = ScreenSchema(
      schemaVersion: '1.0',
      id: 'cycle_test',
      documentType: 'screen',
      product: 'customer_app',
      service: null,
      themeId: 'customer-default',
      themeMode: 'light',
      root: ComponentNode(
        type: 'ScreenTemplate',
        props: const <String, Object?>{},
        slots: <String, List<SchemaNode>>{
          'body': const <SchemaNode>[RefNode(ref: a)],
        },
        actions: const <String, String>{},
        bind: null,
        visibleWhen: null,
      ),
      actions: const <String, ActionDefinition>{},
    );

    final result = await resolveScreenRefs(
      schema: schema,
      loader: _FakeFragmentLoader(docs),
      maxDepth: 50,
      maxFragments: 50,
    );

    expect(
      result.errors.any((e) => e.message.startsWith('Circular reference:')),
      isTrue,
    );
  });

  test('resolveScreenRefs enforces maxDepth budget', () async {
    final fragmentIds = List<String>.generate(5, (i) => 'section:chain_$i');

    final docs = <String, Map<String, Object?>>{};
    for (var i = 0; i < fragmentIds.length; i++) {
      final id = fragmentIds[i];
      final next = i + 1 < fragmentIds.length ? fragmentIds[i + 1] : null;
      docs[id] = next == null ? _fragmentDoc(id) : _refFragmentDoc(id, next);
    }

    final schema = ScreenSchema(
      schemaVersion: '1.0',
      id: 'depth_test',
      documentType: 'screen',
      product: 'customer_app',
      service: null,
      themeId: 'customer-default',
      themeMode: 'light',
      root: ComponentNode(
        type: 'ScreenTemplate',
        props: const <String, Object?>{},
        slots: <String, List<SchemaNode>>{
          'body': <SchemaNode>[RefNode(ref: fragmentIds[0])],
        },
        actions: const <String, String>{},
        bind: null,
        visibleWhen: null,
      ),
      actions: const <String, ActionDefinition>{},
    );

    final result = await resolveScreenRefs(
      schema: schema,
      loader: _FakeFragmentLoader(docs),
      maxDepth: 2,
      maxFragments: 50,
    );

    expect(
      result.errors.any((e) => e.message == 'Exceeded maxDepth=2'),
      isTrue,
    );
  });
}
