const fallbackFragmentDocuments = <String, Map<String, Object?>>{
  'section:customer_welcome_v1': {
    'schemaVersion': '1.0',
    'id': 'section:customer_welcome_v1',
    'documentType': 'fragment',
    'node': {
      'type': 'InfoCard',
      'props': {'title': 'Welcome', 'subtitle': '', 'surface': 'subtle'},
    },
  },
  'fragment:customer_home_services_capsules_v1': {
    'schemaVersion': '1.0',
    'id': 'fragment:customer_home_services_capsules_v1',
    'documentType': 'fragment',
    'node': {
      'type': 'RemoteQuery',
      'props': {
        'key': 'customer_home.services',
        'path': '/v1/service-definitions',
        'dataPath': 'items',
      },
      'slots': {
        'loading': [
          {
            'type': 'InfoCard',
            'props': {
              'title': 'Services',
              'subtitle': 'Loading...',
              'surface': 'subtle',
            },
          },
        ],
        'error': [
          {
            'type': 'InfoCard',
            'props': {
              'title': 'Services',
              'subtitle': 'Unable to load services',
              'surface': 'subtle',
            },
          },
        ],
        'child': [
          {'type': 'ServiceCapsules', 'props': <String, Object?>{}},
        ],
      },
    },
  },
  'fragment:customer_requests_v1': {
    'schemaVersion': '1.0',
    'id': 'fragment:customer_requests_v1',
    'documentType': 'fragment',
    'node': {
      'type': 'RemoteQuery',
      'props': {'key': 'customer.requests', 'path': '/v1/requests'},
      'slots': {
        'loading': [
          {
            'type': 'InfoCard',
            'props': {
              'title': 'Activities',
              'subtitle': 'Loading requests...',
              'surface': 'subtle',
            },
          },
        ],
        'error': [
          {
            'type': 'InfoCard',
            'props': {
              'title': 'Activities',
              'subtitle': 'Could not load requests.',
              'surface': 'subtle',
            },
          },
        ],
        'child': [
          {
            'type': 'Column',
            'props': {
              'spacing': 0,
              'crossAxisAlignment': 'stretch',
              'mainAxisSize': 'min',
            },
            'slots': {
              'children': [
                {
                  'type': 'If',
                  'props': {'valuePath': 'has_requests', 'op': 'isFalse'},
                  'slots': {
                    'then': [
                      {
                        'type': 'InfoCard',
                        'props': {
                          'title': 'Activities',
                          'subtitle': 'No requests yet.',
                          'surface': 'subtle',
                        },
                      },
                    ],
                  },
                },
                {
                  'type': 'If',
                  'props': {'valuePath': 'active', 'op': 'isNotEmpty'},
                  'slots': {
                    'then': [
                      {
                        'type': 'Text',
                        'props': {
                          'text': 'Active requests',
                          'variant': 'title',
                          'weight': 'semibold',
                        },
                      },
                      {
                        'type': 'Gap',
                        'props': {'height': 12},
                      },
                      {
                        'type': 'ForEach',
                        'props': {'itemsPath': 'active'},
                        'slots': {
                          'item': [
                            {
                              'type': 'BoundActionCard',
                              'props': {
                                'titlePath': 'title',
                                'subtitlePath': 'subtitle',
                                'iconPath': 'icon',
                                'routePath': 'route',
                                'surface': 'raised',
                                'density': 'compact',
                                'titleVariant': 'title',
                                'titleWeight': 'semibold',
                                'subtitleVariant': 'body',
                                'subtitleColor': 'muted',
                              },
                            },
                            {
                              'type': 'Gap',
                              'props': {'height': 12},
                            },
                          ],
                        },
                      },
                      {
                        'type': 'Gap',
                        'props': {'height': 12},
                      },
                    ],
                  },
                },
                {
                  'type': 'If',
                  'props': {'valuePath': 'history', 'op': 'isNotEmpty'},
                  'slots': {
                    'then': [
                      {
                        'type': 'Text',
                        'props': {
                          'text': 'History',
                          'variant': 'title',
                          'weight': 'semibold',
                        },
                      },
                      {
                        'type': 'Gap',
                        'props': {'height': 12},
                      },
                      {
                        'type': 'ForEach',
                        'props': {'itemsPath': 'history'},
                        'slots': {
                          'item': [
                            {
                              'type': 'BoundActionCard',
                              'props': {
                                'titlePath': 'title',
                                'subtitlePath': 'subtitle',
                                'iconPath': 'icon',
                                'routePath': 'route',
                                'surface': 'subtle',
                                'density': 'compact',
                                'titleVariant': 'title',
                                'titleWeight': 'semibold',
                                'subtitleVariant': 'body',
                                'subtitleColor': 'muted',
                              },
                            },
                            {
                              'type': 'Gap',
                              'props': {'height': 12},
                            },
                          ],
                        },
                      },
                      {
                        'type': 'Gap',
                        'props': {'height': 12},
                      },
                    ],
                  },
                },
              ],
            },
          },
        ],
      },
    },
  },
  'fragment:request_detail_pharmacy_v1': {
    'schemaVersion': '1.0',
    'id': 'fragment:request_detail_pharmacy_v1',
    'documentType': 'fragment',
    'node': {
      'type': 'Column',
      'props': {
        'spacing': 8,
        'crossAxisAlignment': 'stretch',
        'mainAxisSize': 'min',
      },
      'slots': {
        'children': [
          {
            'type': 'Column',
            'visibleWhen': {
              'valuePath': 'serviceDetails.payload.cart_lines',
              'op': 'isNotEmpty',
            },
            'props': {
              'spacing': 6,
              'crossAxisAlignment': 'stretch',
              'mainAxisSize': 'min',
            },
            'slots': {
              'children': [
                {
                  'type': 'Padding',
                  'props': {'left': 20},
                  'slots': {
                    'child': [
                      {
                        'type': 'Text',
                        'props': {
                          'text': 'Items',
                          'variant': 'subtitle',
                          'weight': 'semibold',
                          'color': 'secondary',
                        },
                      },
                    ],
                  },
                },
                {
                  'type': 'ForEach',
                  'props': {'itemsPath': 'serviceDetails.payload.cart_lines'},
                  'slots': {
                    'item': [
                      {
                        'type': 'CartItem',
                        'props': {
                          'title': r'${item.name}',
                          'subtitle': r'${item.subtitle}',
                          'quantity': r'${item.quantity}',
                          'unitPriceText': r'$${item.price}',
                          'rxRequired': r'${item.rx_required}',
                          'readonly': true,
                          'surface': 'flat',
                          'density': 'compact',
                        },
                      },
                      {
                        'type': 'Gap',
                        'visibleWhen': {
                          'expr':
                              'index < len(data.serviceDetails.payload.cart_lines) - 1',
                        },
                        'props': {'height': 4},
                      },
                    ],
                  },
                },
              ],
            },
          },
          {
            'type': 'CartSummary',
            'visibleWhen': {
              'valuePath': 'serviceDetails.payload.summary_total',
              'op': 'isNotNull',
            },
            'props': {
              'title': 'Summary',
              'linesPath': 'serviceDetails.payload.summary_lines',
              'totalPath': 'serviceDetails.payload.summary_total',
              'surface': 'subtle',
            },
          },
          {
            'type': 'SectionCard',
            'visibleWhen': {
              'valuePath': 'serviceDetails.payload.prescription_uploads',
              'op': 'isNotEmpty',
            },
            'props': {
              'title': 'Prescription',
              'surface': 'subtle',
              'density': 'compact',
              'titleVariant': 'subtitle',
              'titleWeight': 'semibold',
              'titleColor': 'secondary',
              'contentGap': 10,
            },
            'slots': {
              'child': [
                {
                  'type': 'ForEach',
                  'props': {
                    'itemsPath': 'serviceDetails.payload.prescription_uploads',
                  },
                  'slots': {
                    'item': [
                      {
                        'type': 'Text',
                        'props': {
                          'text': r'${item.filename}',
                          'variant': 'body',
                          'weight': 'medium',
                          'color': 'muted',
                        },
                      },
                      {
                        'type': 'Gap',
                        'visibleWhen': {
                          'expr':
                              'index < len(data.serviceDetails.payload.prescription_uploads) - 1',
                        },
                        'props': {'height': 6},
                      },
                    ],
                  },
                },
              ],
            },
          },
        ],
      },
    },
  },
};
