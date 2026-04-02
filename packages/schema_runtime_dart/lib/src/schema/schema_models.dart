sealed class SchemaNode {
  const SchemaNode();
}

final class RefNode extends SchemaNode {
  const RefNode({required this.ref});

  final String ref;
}

final class ComponentNode extends SchemaNode {
  const ComponentNode({
    required this.type,
    required this.props,
    required this.slots,
    required this.actions,
    required this.bind,
    required this.visibleWhen,
  });

  final String type;
  final Map<String, Object?> props;
  final Map<String, List<SchemaNode>> slots;
  final Map<String, String> actions;
  final String? bind;
  final Map<String, Object?>? visibleWhen;
}

final class ActionDefinition {
  const ActionDefinition({
    required this.type,
    this.route,
    this.formId,
    this.eventName,
    this.eventProperties,
  });

  final String type;
  final String? route;
  final String? formId;
  final String? eventName;
  final Map<String, Object?>? eventProperties;
}

final class ScreenSchema {
  const ScreenSchema({
    required this.schemaVersion,
    required this.id,
    required this.documentType,
    required this.product,
    required this.service,
    required this.themeId,
    required this.themeMode,
    required this.root,
    required this.actions,
  });

  final String schemaVersion;
  final String id;
  final String documentType;
  final String product;
  final String? service;
  final String themeId;
  final String? themeMode;
  final ComponentNode root;
  final Map<String, ActionDefinition> actions;
}

final class FragmentSchema {
  const FragmentSchema({
    required this.schemaVersion,
    required this.id,
    required this.documentType,
    required this.node,
  });

  final String schemaVersion;
  final String id;
  final String documentType;
  final ComponentNode node;
}
