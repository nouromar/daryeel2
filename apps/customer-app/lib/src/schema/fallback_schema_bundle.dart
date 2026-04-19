import 'package:flutter_runtime/flutter_runtime.dart';

const fallbackCustomerHomeBundle = SchemaBundle(
  schemaId: 'customer_home',
  schemaVersion: '1.0',
  document: {
    'schemaVersion': '1.0',
    'id': 'customer_home',
    'documentType': 'screen',
    'product': 'customer_app',
    'themeId': 'custome-black-white-clear',
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
            'props': {
              'headerGap': 0,
              'bodyPadding': {'left': 8, 'top': 0, 'right': 8, 'bottom': 8},
              'footerPadding': {'left': 8, 'top': 0, 'right': 8, 'bottom': 8},
            },
            'slots': {
              'body': [
                {
                  'type': 'Align',
                  'props': {'alignment': 'centerRight'},
                  'slots': {
                    'child': [
                      {
                        'type': 'IconButton',
                        'props': {
                          'codePoint': 58837,
                          'family': 'material_icons',
                          'size': 20,
                          'semanticLabel': 'Refresh',
                        },
                        'actions': {'tap': 'refresh_activities'},
                      },
                    ],
                  },
                },
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
      'refresh_activities': {
        'type': 'customer_requests_refresh',
        'value': null,
      },
    },
  },
);
