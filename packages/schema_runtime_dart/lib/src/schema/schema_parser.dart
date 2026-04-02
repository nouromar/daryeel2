import 'schema_models.dart';

class SchemaParseError {
  const SchemaParseError({required this.path, required this.message});

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

class SchemaParseResult<T> {
  const SchemaParseResult({required this.value, required this.errors});

  final T? value;
  final List<SchemaParseError> errors;

  bool get isValid => value != null && errors.isEmpty;
}

SchemaParseResult<ComponentNode> parseComponentNode(Map<String, Object?> json) {
  final errors = <SchemaParseError>[];
  final node = _parseComponentNode(json, path: r'$', errors: errors);
  if (node == null) {
    return SchemaParseResult(value: null, errors: errors);
  }
  return SchemaParseResult(value: node, errors: errors);
}

SchemaParseResult<FragmentSchema> parseFragmentSchema(
  Map<String, Object?> json,
) {
  final errors = <SchemaParseError>[];

  String? requiredString(String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    errors.add(
      SchemaParseError(path: key, message: 'Expected non-empty string'),
    );
    return null;
  }

  final schemaVersion = requiredString('schemaVersion');
  final id = requiredString('id');
  final documentType = requiredString('documentType');

  final nodeRaw = json['node'];
  final node = nodeRaw is Map
      ? _parseComponentNode(
          Map<String, Object?>.from(nodeRaw.cast<String, Object?>()),
          path: 'node',
          errors: errors,
        )
      : null;
  if (node == null) {
    errors.add(
      const SchemaParseError(path: 'node', message: 'Expected object'),
    );
  }

  if (schemaVersion == null ||
      id == null ||
      documentType == null ||
      documentType != 'fragment' ||
      node == null) {
    if (documentType != null && documentType != 'fragment') {
      errors.add(
        const SchemaParseError(
          path: 'documentType',
          message: 'Expected "fragment"',
        ),
      );
    }
    return SchemaParseResult(value: null, errors: errors);
  }

  return SchemaParseResult(
    value: FragmentSchema(
      schemaVersion: schemaVersion,
      id: id,
      documentType: documentType,
      node: node,
    ),
    errors: errors,
  );
}

SchemaParseResult<ScreenSchema> parseScreenSchema(Map<String, Object?> json) {
  final errors = <SchemaParseError>[];

  String? requiredString(String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    errors.add(
      SchemaParseError(path: key, message: 'Expected non-empty string'),
    );
    return null;
  }

  final schemaVersion = requiredString('schemaVersion');
  final id = requiredString('id');
  final documentType = requiredString('documentType');
  final product = requiredString('product');
  final themeId = requiredString('themeId');

  final service = json['service'] as String?;
  final themeMode = json['themeMode'] as String?;

  final rootRaw = json['root'];
  final root = rootRaw is Map
      ? _parseComponentNode(
          Map<String, Object?>.from(rootRaw.cast<String, Object?>()),
          path: 'root',
          errors: errors,
        )
      : null;
  if (root == null) {
    errors.add(
      const SchemaParseError(path: 'root', message: 'Expected object'),
    );
  }

  final actions = <String, ActionDefinition>{};
  final actionsRaw = json['actions'];
  if (actionsRaw is Map) {
    for (final entry in actionsRaw.entries) {
      if (entry.key is! String) continue;
      final value = entry.value;
      if (value is! Map) {
        errors.add(
          SchemaParseError(
            path: 'actions.${entry.key}',
            message: 'Expected object',
          ),
        );
        continue;
      }
      final actionType = value['type'];
      if (actionType is! String || actionType.isEmpty) {
        errors.add(
          SchemaParseError(
            path: 'actions.${entry.key}.type',
            message: 'Expected non-empty string',
          ),
        );
        continue;
      }

      Map<String, Object?>? eventProperties;
      final eventPropsRaw = value['eventProperties'];
      if (eventPropsRaw is Map) {
        eventProperties = Map<String, Object?>.from(
          eventPropsRaw.cast<String, Object?>(),
        );
      }

      actions[entry.key as String] = ActionDefinition(
        type: actionType,
        route: value['route'] as String?,
        formId: value['formId'] as String?,
        eventName: value['eventName'] as String?,
        eventProperties: eventProperties,
      );
    }
  }

  if (schemaVersion == null ||
      id == null ||
      documentType == null ||
      product == null ||
      themeId == null ||
      root == null) {
    return SchemaParseResult(value: null, errors: errors);
  }

  return SchemaParseResult(
    value: ScreenSchema(
      schemaVersion: schemaVersion,
      id: id,
      documentType: documentType,
      product: product,
      service: service,
      themeId: themeId,
      themeMode: themeMode,
      root: root,
      actions: actions,
    ),
    errors: errors,
  );
}

ComponentNode? _parseComponentNode(
  Map<String, Object?> json, {
  required String path,
  required List<SchemaParseError> errors,
}) {
  final type = json['type'];
  if (type is! String || type.isEmpty) {
    errors.add(
      SchemaParseError(
        path: '$path.type',
        message: 'Expected non-empty string',
      ),
    );
    return null;
  }

  final propsRaw = json['props'];
  final props = propsRaw is Map
      ? Map<String, Object?>.from(propsRaw.cast<String, Object?>())
      : const <String, Object?>{};

  final actionsRaw = json['actions'];
  final actions = <String, String>{};
  if (actionsRaw is Map) {
    for (final entry in actionsRaw.entries) {
      if (entry.key is String && entry.value is String) {
        actions[entry.key as String] = entry.value as String;
      }
    }
  }

  final slots = <String, List<SchemaNode>>{};
  final slotsRaw = json['slots'];
  if (slotsRaw is Map) {
    for (final entry in slotsRaw.entries) {
      if (entry.key is! String) continue;
      final childrenRaw = entry.value;
      if (childrenRaw is! List) {
        errors.add(
          SchemaParseError(
            path: '$path.slots.${entry.key}',
            message: 'Expected array',
          ),
        );
        continue;
      }

      final children = <SchemaNode>[];
      for (var index = 0; index < childrenRaw.length; index++) {
        final child = childrenRaw[index];
        if (child is! Map) {
          errors.add(
            SchemaParseError(
              path: '$path.slots.${entry.key}[$index]',
              message: 'Expected object',
            ),
          );
          continue;
        }
        final childMap = Map<String, Object?>.from(
          child.cast<String, Object?>(),
        );
        if (childMap.containsKey('ref') && !childMap.containsKey('type')) {
          final ref = childMap['ref'];
          if (ref is String && ref.isNotEmpty) {
            children.add(RefNode(ref: ref));
          } else {
            errors.add(
              SchemaParseError(
                path: '$path.slots.${entry.key}[$index].ref',
                message: 'Expected non-empty string',
              ),
            );
          }
          continue;
        }

        final parsed = _parseComponentNode(
          childMap,
          path: '$path.slots.${entry.key}[$index]',
          errors: errors,
        );
        if (parsed != null) {
          children.add(parsed);
        }
      }
      slots[entry.key as String] = children;
    }
  }

  final bind = json['bind'] as String?;
  final visibleWhenRaw = json['visibleWhen'];
  final visibleWhen = visibleWhenRaw is Map
      ? Map<String, Object?>.from(visibleWhenRaw.cast<String, Object?>())
      : null;

  return ComponentNode(
    type: type,
    props: props,
    slots: slots,
    actions: actions,
    bind: bind,
    visibleWhen: visibleWhen,
  );
}
