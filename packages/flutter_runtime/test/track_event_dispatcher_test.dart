import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TrackEventSchemaActionDispatcher calls handler', (tester) async {
    final recorded = <String, Object?>{};

    final handler = _RecordingTrackEventHandler(
      onCall: (name, props) {
        recorded['name'] = name;
        recorded['props'] = props;
      },
    );

    final dispatcher = TrackEventSchemaActionDispatcher(
      trackEventHandler: handler,
    );

    final action = ActionDefinition(
      type: SchemaActionTypes.trackEvent,
      eventName: 'customer.test',
      eventProperties: <String, Object?>{
        'ok': true,
        'count': 2,
        'msg': 'hello',
        'nested': <String, Object?>{'a': 1},
      },
    );

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await dispatcher.dispatch(ctx, action);

    expect(recorded['name'], 'customer.test');
    final props = recorded['props'] as Map<String, Object?>;
    expect(props['ok'], true);
    expect(props['count'], 2);
    expect(props['msg'], 'hello');
    expect(props.containsKey('nested'), isFalse);
  });
}

class _RecordingTrackEventHandler extends TrackEventHandler {
  _RecordingTrackEventHandler({required this.onCall});

  final void Function(String, Map<String, Object?>) onCall;

  @override
  Future<void> trackEvent(
    String eventName, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {
    onCall(eventName, properties);
  }
}
