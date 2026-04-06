export type SchemaNode = RefNode | ComponentNode;

export interface RefNode {
  readonly kind: 'ref';
  readonly ref: string;
}

export interface ComponentNode {
  readonly kind: 'component';
  readonly type: string;
  readonly props: Record<string, unknown>;
  readonly slots: Record<string, SchemaNode[]>;
  readonly actions: Record<string, string>;
  readonly bind?: string;
  readonly visibleWhen?: Record<string, unknown>;
}

export interface ActionDefinition {
  readonly type: string;
  readonly route?: string;
  readonly formId?: string;
  readonly modalId?: string;
  readonly dataSource?: string;
  readonly value?: unknown;
  readonly eventName?: string;
  readonly eventProperties?: Record<string, unknown>;
}

export interface ScreenSchema {
  readonly schemaVersion: string;
  readonly id: string;
  readonly documentType: string;
  readonly product: string;
  readonly service?: string;
  readonly themeId: string;
  readonly themeMode?: string;
  readonly root: ComponentNode;
  readonly actions: Record<string, ActionDefinition>;
}

export interface FragmentSchema {
  readonly schemaVersion: string;
  readonly id: string;
  readonly documentType: string;
  readonly node: ComponentNode;
}

export function makeRefNode(ref: string): RefNode {
  return { kind: 'ref', ref };
}

export function makeComponentNode(params: Omit<ComponentNode, 'kind'>): ComponentNode {
  return {
    kind: 'component',
    ...params,
  };
}
