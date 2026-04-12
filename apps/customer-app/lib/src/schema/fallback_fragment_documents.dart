const fallbackFragmentDocuments = <String, Map<String, Object?>>{
  'section:customer_welcome_v1': {
    'schemaVersion': '1.0',
    'id': 'section:customer_welcome_v1',
    'documentType': 'fragment',
    'node': {
      'type': 'InfoCard',
      'props': {
        'title': 'Welcome',
        'subtitle': 'Resolved from fragment',
        'surface': 'subtle',
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
              'spacing': 12,
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
                  'props': {'valuePath': 'attention', 'op': 'isNotEmpty'},
                  'slots': {
                    'then': [
                      {
                        'type': 'Text',
                        'props': {
                          'text': 'Needs attention',
                          'variant': 'title',
                          'weight': 'semibold',
                        },
                      },
                      {
                        'type': 'ForEach',
                        'props': {'itemsPath': 'attention'},
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
            'type': 'If',
            'props': {
              'valuePath': 'serviceDetails.summary.items',
              'op': 'isNotEmpty',
            },
            'slots': {
              'then': [
                {
                  'type': 'Text',
                  'props': {
                    'text': 'Items',
                    'variant': 'title',
                    'weight': 'semibold',
                  },
                },
                {
                  'type': 'ForEach',
                  'props': {'itemsPath': 'serviceDetails.summary.items'},
                  'slots': {
                    'item': [
                      {
                        'type': 'Text',
                        'props': {'text': r'${item.title} ${item.subtitle}'},
                      },
                      {
                        'type': 'Gap',
                        'props': {'height': 4},
                      },
                    ],
                  },
                },
              ],
            },
          },
          {
            'type': 'InfoCard',
            'visibleWhen': {
              'expr':
                  "data.serviceDetails.summary.summaryText != null and data.serviceDetails.summary.summaryText != ''",
            },
            'props': {
              'title': 'Summary',
              'subtitle': r'${data.serviceDetails.summary.summaryText}',
              'surface': 'flat',
            },
          },
          {
            'type': 'If',
            'props': {
              'valuePath': 'serviceDetails.prescriptionUploads',
              'op': 'isNotEmpty',
            },
            'slots': {
              'then': [
                {
                  'type': 'Text',
                  'props': {
                    'text': 'Prescription',
                    'variant': 'title',
                    'weight': 'semibold',
                  },
                },
                {
                  'type': 'ForEach',
                  'props': {'itemsPath': 'serviceDetails.prescriptionUploads'},
                  'slots': {
                    'item': [
                      {
                        'type': 'ActionCard',
                        'props': {
                          'title': r'${item.title}',
                          'subtitle': r'${item.subtitle}',
                          'surface': 'flat',
                        },
                      },
                      {
                        'type': 'Gap',
                        'props': {'height': 8},
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
