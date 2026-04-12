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
      'type': 'BottomTabs',
      'props': {
        'tabs': [
          {'id': 'home', 'label': 'Home', 'icon': 'home'},
          {'id': 'activities', 'label': 'Activities', 'icon': 'history'},
          {'id': 'account', 'label': 'Account', 'icon': 'person'},
        ],
      },
      'slots': {
        'home': [
          {
            'type': 'ScreenTemplate',
            'slots': {
              'body': [
                {'ref': 'section:customer_welcome_v1'},
                {
                  'type': 'Gap',
                  'props': {'height': 12},
                },
                {
                  'type': 'ActionCard',
                  'props': {
                    'title': 'Ambulance',
                    'subtitle': 'Request an ambulance',
                    'icon': 'ambulance',
                    'surface': 'raised',
                  },
                  'actions': {'tap': 'go_ambulance'},
                },
                {
                  'type': 'Gap',
                  'props': {'height': 12},
                },
                {
                  'type': 'ActionCard',
                  'props': {
                    'title': 'Home Visit',
                    'subtitle': 'Request a home visit',
                    'icon': 'home',
                    'surface': 'raised',
                  },
                  'actions': {'tap': 'go_home_visit'},
                },
                {
                  'type': 'Gap',
                  'props': {'height': 12},
                },
                {
                  'type': 'ActionCard',
                  'props': {
                    'title': 'Pharmacy',
                    'subtitle': 'Request pharmacy delivery',
                    'icon': 'pharmacy',
                    'surface': 'raised',
                  },
                  'actions': {'tap': 'go_pharmacy'},
                },
              ],
            },
          },
        ],
        'activities': [
          {
            'type': 'ScreenTemplate',
            'slots': {
              'body': [
                {'ref': 'fragment:customer_requests_v1'},
              ],
            },
          },
        ],
        'account': [
          {
            'type': 'ScreenTemplate',
            'slots': {
              'body': [
                {
                  'type': 'InfoCard',
                  'props': {
                    'title': 'Account',
                    'subtitle': 'Coming soon',
                    'surface': 'subtle',
                  },
                },
              ],
            },
          },
        ],
      },
    },
    'actions': {
      'go_ambulance': {
        'type': 'navigate',
        'route': 'customer.schema_screen',
        'value': {
          'screenId': 'customer_request_ambulance',
          'title': 'Ambulance',
        },
      },
      'go_home_visit': {
        'type': 'navigate',
        'route': 'customer.schema_screen',
        'value': {
          'screenId': 'customer_request_home_visit',
          'title': 'Home Visit',
        },
      },
      'go_pharmacy': {
        'type': 'navigate',
        'route': 'customer.schema_screen',
        'value': {
          'screenId': 'pharmacy_shop',
          'title': 'Pharmacy',
          'chromePreset': 'pharmacy_cart_badge',
        },
      },
    },
  },
);
