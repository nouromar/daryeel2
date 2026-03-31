import 'package:flutter_runtime/flutter_runtime.dart';

const fallbackCustomerHomeBundle = SchemaBundle(
  schemaId: 'customer_home',
  schemaVersion: '1.0',
  document: {
    'schemaVersion': '1.0',
    'id': 'customer_home',
    'documentType': 'screen',
    'product': 'customer_app',
    'themeId': 'customer-default',
    'themeMode': 'light',
    'root': {
      'type': 'ScreenTemplate',
      'slots': {
        'body': [
          {'ref': 'section:customer_welcome_v1'},
          {
            'type': 'InfoCard',
            'props': {
              'title': 'Daryeel2',
              'subtitle': 'Bundled customer home fallback',
              'variant': 'default',
              'surface': 'raised',
            },
          },
        ],
        'footer': [
          {
            'type': 'PrimaryActionBar',
            'props': {
              'primaryLabel': 'Open schema service',
              'tone': 'brand',
              'size': 'large',
            },
            'actions': {'primary': 'open_schema_service'},
          },
        ],
      },
    },
    'actions': {
      'open_schema_service': {'type': 'navigate', 'route': 'schema.service'},
    },
  },
);
