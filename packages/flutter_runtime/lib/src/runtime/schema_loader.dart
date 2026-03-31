import 'runtime_models.dart';

abstract class SchemaLoader {
  Future<SchemaBundle> loadScreen(RuntimeScreenRequest request);
}
