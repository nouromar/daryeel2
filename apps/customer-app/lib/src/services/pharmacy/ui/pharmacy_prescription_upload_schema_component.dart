import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'pharmacy_prescription_upload_widget.dart';

void registerPharmacyPrescriptionUploadSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('PharmacyPrescriptionUpload', (node, _) {
    return const PharmacyPrescriptionUploadWidget();
  });
}

