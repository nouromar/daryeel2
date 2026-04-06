import {
  type ActionDefinition,
  type ComponentNode,
  type FragmentSchema,
  type SchemaNode,
  type ScreenSchema,
  makeComponentNode,
  makeRefNode,
} from './schema_models.js';

export interface SchemaParseError {
  readonly path: string;
  readonly message: string;
}

export interface SchemaParseResult<T> {
  readonly value: T | null;
  readonly errors: SchemaParseError[];
  readonly isValid: boolean;
}

function result<T>(value: T | null, errors: SchemaParseError[]): SchemaParseResult<T> {
  return { value, errors, isValid: value !== null && errors.length === 0 };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requiredNonEmptyString(
  json: Record<string, unknown>,
  key: string,
  errors: SchemaParseError[],
): string | null {
  const value = json[key];
  if (typeof value === 'string' && value.length > 0) return value;
  errors.push({ path: key, message: 'Expected non-empty string' });
  return null;
}

export function parseComponentNode(json: Record<string, unknown>): SchemaParseResult<ComponentNode> {
  const errors: SchemaParseError[] = [];
  const node = parseComponentNodeInternal(json, '$', errors);
  return node ? result(node, errors) : result<ComponentNode>(null, errors);
}

export function parseFragmentSchema(json: Record<string, unknown>): SchemaParseResult<FragmentSchema> {
  const errors: SchemaParseError[] = [];

  const schemaVersion = requiredNonEmptyString(json, 'schemaVersion', errors);
  const id = requiredNonEmptyString(json, 'id', errors);
  const documentType = requiredNonEmptyString(json, 'documentType', errors);

  const nodeRaw = json['node'];
  const node = isRecord(nodeRaw) ? parseComponentNodeInternal(nodeRaw, 'node', errors) : null;
  if (!node) {
    errors.push({ path: 'node', message: 'Expected object' });
  }

  if (!schemaVersion || !id || !documentType || documentType !== 'fragment' || !node) {
    if (documentType && documentType !== 'fragment') {
      errors.push({ path: 'documentType', message: 'Expected "fragment"' });
    }
    return result<FragmentSchema>(null, errors);
  }

  return result(
    {
      schemaVersion,
      id,
      documentType,
      node,
    },
    errors,
  );
}

export function parseScreenSchema(json: Record<string, unknown>): SchemaParseResult<ScreenSchema> {
  const errors: SchemaParseError[] = [];

  const schemaVersion = requiredNonEmptyString(json, 'schemaVersion', errors);
  const id = requiredNonEmptyString(json, 'id', errors);
  const documentType = requiredNonEmptyString(json, 'documentType', errors);
  const product = requiredNonEmptyString(json, 'product', errors);
  const themeId = requiredNonEmptyString(json, 'themeId', errors);

  const service = typeof json['service'] === 'string' ? (json['service'] as string) : undefined;
  const themeMode = typeof json['themeMode'] === 'string' ? (json['themeMode'] as string) : undefined;

  const rootRaw = json['root'];
  const root = isRecord(rootRaw) ? parseComponentNodeInternal(rootRaw, 'root', errors) : null;
  if (!root) {
    errors.push({ path: 'root', message: 'Expected object' });
  }

  const actions: Record<string, ActionDefinition> = {};
  const actionsRaw = json['actions'];
  if (isRecord(actionsRaw)) {
    for (const [key, rawValue] of Object.entries(actionsRaw)) {
      if (!isRecord(rawValue)) {
        errors.push({ path: `actions.${key}`, message: 'Expected object' });
        continue;
      }

      const actionType = rawValue['type'];
      if (typeof actionType !== 'string' || actionType.length === 0) {
        errors.push({ path: `actions.${key}.type`, message: 'Expected non-empty string' });
        continue;
      }

      const eventPropertiesRaw = rawValue['eventProperties'];
      const eventProperties = isRecord(eventPropertiesRaw)
        ? (eventPropertiesRaw as Record<string, unknown>)
        : undefined;

      actions[key] = {
        type: actionType,
        route: typeof rawValue['route'] === 'string' ? (rawValue['route'] as string) : undefined,
        formId: typeof rawValue['formId'] === 'string' ? (rawValue['formId'] as string) : undefined,
        modalId: typeof rawValue['modalId'] === 'string' ? (rawValue['modalId'] as string) : undefined,
        dataSource:
          typeof rawValue['dataSource'] === 'string' ? (rawValue['dataSource'] as string) : undefined,
        value: rawValue['value'],
        eventName:
          typeof rawValue['eventName'] === 'string' ? (rawValue['eventName'] as string) : undefined,
        eventProperties,
      };
    }
  }

  if (!schemaVersion || !id || !documentType || !product || !themeId || !root) {
    return result<ScreenSchema>(null, errors);
  }

  return result(
    {
      schemaVersion,
      id,
      documentType,
      product,
      service,
      themeId,
      themeMode,
      root,
      actions,
    },
    errors,
  );
}

function parseComponentNodeInternal(
  json: Record<string, unknown>,
  path: string,
  errors: SchemaParseError[],
): ComponentNode | null {
  const type = json['type'];
  if (typeof type !== 'string' || type.length === 0) {
    errors.push({ path: `${path}.type`, message: 'Expected non-empty string' });
    return null;
  }

  const propsRaw = json['props'];
  const props = isRecord(propsRaw) ? (propsRaw as Record<string, unknown>) : {};

  const actionsRaw = json['actions'];
  const actions: Record<string, string> = {};
  if (isRecord(actionsRaw)) {
    for (const [key, value] of Object.entries(actionsRaw)) {
      if (typeof value === 'string') actions[key] = value;
    }
  }

  const slots: Record<string, SchemaNode[]> = {};
  const slotsRaw = json['slots'];
  if (isRecord(slotsRaw)) {
    for (const [slotName, childrenRaw] of Object.entries(slotsRaw)) {
      if (!Array.isArray(childrenRaw)) {
        errors.push({ path: `${path}.slots.${slotName}`, message: 'Expected array' });
        continue;
      }

      const children: SchemaNode[] = [];
      for (let index = 0; index < childrenRaw.length; index++) {
        const child = childrenRaw[index];
        if (!isRecord(child)) {
          errors.push({ path: `${path}.slots.${slotName}[${index}]`, message: 'Expected object' });
          continue;
        }

        // Ref node (must NOT have type).
        if ('ref' in child && !('type' in child)) {
          const refValue = child['ref'];
          if (typeof refValue === 'string' && refValue.length > 0) {
            children.push(makeRefNode(refValue));
          } else {
            errors.push({
              path: `${path}.slots.${slotName}[${index}].ref`,
              message: 'Expected non-empty string',
            });
          }
          continue;
        }

        const parsed = parseComponentNodeInternal(child, `${path}.slots.${slotName}[${index}]`, errors);
        if (parsed) children.push(parsed);
      }

      slots[slotName] = children;
    }
  }

  const bind = typeof json['bind'] === 'string' ? (json['bind'] as string) : undefined;

  const visibleWhenRaw = json['visibleWhen'];
  const visibleWhen = isRecord(visibleWhenRaw)
    ? (visibleWhenRaw as Record<string, unknown>)
    : undefined;

  return makeComponentNode({
    type,
    props,
    slots,
    actions,
    bind,
    visibleWhen,
  });
}
