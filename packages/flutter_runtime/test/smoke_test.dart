import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flutter_runtime smoke', () {
    // Ensures the runtime package compiles and exports schema runtime symbols.
    expect(RefResolutionError, isNotNull);
  });
}
