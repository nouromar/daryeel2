import {
  type ComponentNode,
  type RefNode,
  type SchemaNode,
  type ScreenSchema,
  makeComponentNode,
} from './schema_models.js';
import { parseFragmentSchema } from './schema_parser.js';

export interface FragmentDocumentLoader {
  loadFragmentDocument(fragmentId: string): Promise<Record<string, unknown>>;
}

export interface RefResolutionError {
  readonly path: string;
  readonly ref: string;
  readonly message: string;
}

export interface RefResolutionResult {
  readonly schema: ScreenSchema;
  readonly errors: RefResolutionError[];
  readonly isFullyResolved: boolean;
}

function isRefNode(node: SchemaNode): node is RefNode {
  return (node as RefNode).kind === 'ref';
}

function isComponentNode(node: SchemaNode): node is ComponentNode {
  return (node as ComponentNode).kind === 'component';
}

export async function resolveScreenRefs(params: {
  schema: ScreenSchema;
  loader: FragmentDocumentLoader;
  maxDepth?: number;
}): Promise<RefResolutionResult> {
  const { schema, loader, maxDepth = 32 } = params;

  const errors: RefResolutionError[] = [];
  const cache = new Map<string, ComponentNode>();

  const resolveNode = async (
    node: SchemaNode,
    ctx: { path: string; stack: string[]; depth: number },
  ): Promise<SchemaNode> => {
    if (ctx.depth > maxDepth) {
      errors.push({
        path: ctx.path,
        ref: ctx.stack.length === 0 ? '<depth>' : ctx.stack[ctx.stack.length - 1]!,
        message: `Exceeded maxDepth=${maxDepth}`,
      });
      return node;
    }

    if (isRefNode(node)) {
      const ref = node.ref;

      if (ctx.stack.includes(ref)) {
        errors.push({
          path: ctx.path,
          ref,
          message: `Circular reference: ${[...ctx.stack, ref].join(' -> ')}`,
        });
        return node;
      }

      const cached = cache.get(ref);
      if (cached) return cached;

      let raw: Record<string, unknown>;
      try {
        raw = await loader.loadFragmentDocument(ref);
      } catch (e) {
        errors.push({ path: ctx.path, ref, message: `Failed to load fragment: ${String(e)}` });
        return node;
      }

      const parsed = parseFragmentSchema(raw);
      if (!parsed.value) {
        errors.push({
          path: ctx.path,
          ref,
          message: `Invalid fragment document: ${parsed.errors.map((x) => `${x.path}: ${x.message}`).join('; ')}`,
        });
        return node;
      }

      const resolved = await resolveNode(parsed.value.node, {
        path: `${ctx.path}(ref:${ref})`,
        stack: [...ctx.stack, ref],
        depth: ctx.depth + 1,
      });

      if (isComponentNode(resolved)) {
        cache.set(ref, resolved);
      }

      return resolved;
    }

    if (isComponentNode(node)) {
      let didChange = false;
      const resolvedSlots: Record<string, SchemaNode[]> = {};

      for (const [slotName, children] of Object.entries(node.slots)) {
        const out: SchemaNode[] = [];
        for (let index = 0; index < children.length; index++) {
          const child = children[index]!;
          const resolvedChild = await resolveNode(child, {
            path: `${ctx.path}.slots.${slotName}[${index}]`,
            stack: ctx.stack,
            depth: ctx.depth,
          });
          out.push(resolvedChild);
          if (resolvedChild !== child) didChange = true;
        }
        resolvedSlots[slotName] = out;
      }

      if (!didChange) return node;

      return makeComponentNode({
        type: node.type,
        props: node.props,
        slots: resolvedSlots,
        actions: node.actions,
        bind: node.bind,
        visibleWhen: node.visibleWhen,
      });
    }

    return node;
  };

  const resolvedRoot = await resolveNode(schema.root, { path: 'root', stack: [], depth: 0 });

  const root = isComponentNode(resolvedRoot) ? resolvedRoot : schema.root;

  const nextSchema: ScreenSchema = {
    schemaVersion: schema.schemaVersion,
    id: schema.id,
    documentType: schema.documentType,
    product: schema.product,
    service: schema.service,
    themeId: schema.themeId,
    themeMode: schema.themeMode,
    root,
    actions: schema.actions,
  };

  return {
    schema: nextSchema,
    errors,
    isFullyResolved: errors.length === 0,
  };
}
