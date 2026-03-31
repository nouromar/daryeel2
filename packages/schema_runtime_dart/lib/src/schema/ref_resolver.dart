import 'schema_models.dart';
import 'schema_parser.dart';

abstract class FragmentDocumentLoader {
  Future<Map<String, Object?>> loadFragmentDocument(String fragmentId);
}

class RefResolutionError {
  const RefResolutionError({
    required this.path,
    required this.ref,
    required this.message,
  });

  final String path;
  final String ref;
  final String message;

  @override
  String toString() => '$path ($ref): $message';
}

class RefResolutionResult {
  const RefResolutionResult({required this.schema, required this.errors});

  final ScreenSchema schema;
  final List<RefResolutionError> errors;

  bool get isFullyResolved => errors.isEmpty;
}

Future<RefResolutionResult> resolveScreenRefs({
  required ScreenSchema schema,
  required FragmentDocumentLoader loader,
  int maxDepth = 32,
}) async {
  final errors = <RefResolutionError>[];
  final cache = <String, ComponentNode>{};

  Future<SchemaNode> resolveNode(
    SchemaNode node, {
    required String path,
    required List<String> stack,
    required int depth,
  }) async {
    if (depth > maxDepth) {
      errors.add(
        RefResolutionError(
          path: path,
          ref: stack.isEmpty ? '<depth>' : stack.last,
          message: 'Exceeded maxDepth=$maxDepth',
        ),
      );
      return node;
    }

    if (node is RefNode) {
      final ref = node.ref;
      if (stack.contains(ref)) {
        errors.add(
          RefResolutionError(
            path: path,
            ref: ref,
            message: 'Circular reference: ${[...stack, ref].join(' -> ')}',
          ),
        );
        return node;
      }

      final cached = cache[ref];
      if (cached != null) {
        return cached;
      }

      Map<String, Object?> raw;
      try {
        raw = await loader.loadFragmentDocument(ref);
      } catch (error) {
        errors.add(
          RefResolutionError(
            path: path,
            ref: ref,
            message: 'Failed to load fragment: $error',
          ),
        );
        return node;
      }

      final parsed = parseFragmentSchema(raw);
      final fragment = parsed.value;
      if (fragment == null) {
        errors.add(
          RefResolutionError(
            path: path,
            ref: ref,
            message: 'Invalid fragment document: ${parsed.errors.join('; ')}',
          ),
        );
        return node;
      }

      final resolved = await resolveNode(
        fragment.node,
        path: '$path(ref:$ref)',
        stack: [...stack, ref],
        depth: depth + 1,
      );

      if (resolved is ComponentNode) {
        cache[ref] = resolved;
      }
      return resolved;
    }

    if (node is ComponentNode) {
      var didChange = false;
      final resolvedSlots = <String, List<SchemaNode>>{};

      for (final entry in node.slots.entries) {
        final slotName = entry.key;
        final children = entry.value;
        final resolvedChildren = <SchemaNode>[];
        for (var index = 0; index < children.length; index++) {
          final child = children[index];
          final resolvedChild = await resolveNode(
            child,
            path: '$path.slots.$slotName[$index]',
            stack: stack,
            depth: depth,
          );
          resolvedChildren.add(resolvedChild);
          if (!identical(resolvedChild, child)) {
            didChange = true;
          }
        }
        resolvedSlots[slotName] = resolvedChildren;
      }

      if (!didChange) {
        return node;
      }

      return ComponentNode(
        type: node.type,
        props: node.props,
        slots: resolvedSlots,
        actions: node.actions,
        bind: node.bind,
        visibleWhen: node.visibleWhen,
      );
    }

    return node;
  }

  final resolvedRoot = await resolveNode(
    schema.root,
    path: 'root',
    stack: const [],
    depth: 0,
  );

  return RefResolutionResult(
    schema: ScreenSchema(
      schemaVersion: schema.schemaVersion,
      id: schema.id,
      documentType: schema.documentType,
      product: schema.product,
      service: schema.service,
      themeId: schema.themeId,
      themeMode: schema.themeMode,
      root: resolvedRoot is ComponentNode ? resolvedRoot : schema.root,
      actions: schema.actions,
    ),
    errors: errors,
  );
}
