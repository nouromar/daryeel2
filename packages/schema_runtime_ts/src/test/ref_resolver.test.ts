import test from 'node:test';
import assert from 'node:assert/strict';

import {
  makeComponentNode,
  makeRefNode,
  type ScreenSchema,
} from '../schema/schema_models.js';
import { resolveScreenRefs } from '../schema/ref_resolver.js';
import type { FragmentDocumentLoader } from '../schema/ref_resolver.js';

class InMemoryLoader implements FragmentDocumentLoader {
  constructor(private readonly docs: Record<string, Record<string, unknown>>) {}
  async loadFragmentDocument(fragmentId: string): Promise<Record<string, unknown>> {
    const doc = this.docs[fragmentId];
    if (!doc) throw new Error(`missing:${fragmentId}`);
    return doc;
  }
}

function makeScreen(root: ReturnType<typeof makeComponentNode>): ScreenSchema {
  return {
    schemaVersion: '1.0',
    id: 'screen:demo',
    documentType: 'screen',
    product: 'customer_app',
    themeId: 'customer-default',
    root,
    actions: {},
  };
}

test('resolveScreenRefs resolves fragment ref into component node', async () => {
  const schema = makeScreen(
    makeComponentNode({
      type: 'ScreenTemplate',
      props: {},
      slots: { body: [makeRefNode('section:welcome')] },
      actions: {},
    }),
  );

  const loader = new InMemoryLoader({
    'section:welcome': {
      schemaVersion: '1.0',
      id: 'section:welcome',
      documentType: 'fragment',
      node: {
        type: 'InfoCard',
        props: { title: 'Welcome' },
      },
    },
  });

  const out = await resolveScreenRefs({ schema, loader });
  assert.equal(out.errors.length, 0);
  const body = out.schema.root.slots.body;
  assert.equal(body.length, 1);
  assert.equal(body[0]?.kind, 'component');
  assert.equal((body[0] as any).type, 'InfoCard');
});

test('resolveScreenRefs detects circular references', async () => {
  const schema = makeScreen(
    makeComponentNode({
      type: 'ScreenTemplate',
      props: {},
      slots: { body: [makeRefNode('a')] },
      actions: {},
    }),
  );

  const loader = new InMemoryLoader({
    a: { schemaVersion: '1.0', id: 'a', documentType: 'fragment', node: { type: 'X', slots: { body: [{ ref: 'b' }] } } },
    b: { schemaVersion: '1.0', id: 'b', documentType: 'fragment', node: { type: 'Y', slots: { body: [{ ref: 'a' }] } } },
  });

  const out = await resolveScreenRefs({ schema, loader });
  assert.ok(out.errors.some((e) => e.message.toLowerCase().includes('circular reference')));
});

test('resolveScreenRefs leaves ref node when fragment missing', async () => {
  const schema = makeScreen(
    makeComponentNode({
      type: 'ScreenTemplate',
      props: {},
      slots: { body: [makeRefNode('missing')] },
      actions: {},
    }),
  );

  const loader = new InMemoryLoader({});
  const out = await resolveScreenRefs({ schema, loader });

  assert.equal(out.errors.length, 1);
  assert.equal(out.schema.root.slots.body[0]?.kind, 'ref');
});

test('resolveScreenRefs enforces maxDepth', async () => {
  const schema = makeScreen(
    makeComponentNode({
      type: 'ScreenTemplate',
      props: {},
      slots: { body: [makeRefNode('a')] },
      actions: {},
    }),
  );

  const loader = new InMemoryLoader({
    a: { schemaVersion: '1.0', id: 'a', documentType: 'fragment', node: { type: 'X', slots: { body: [{ ref: 'b' }] } } },
    b: { schemaVersion: '1.0', id: 'b', documentType: 'fragment', node: { type: 'Y', slots: { body: [{ ref: 'c' }] } } },
    c: { schemaVersion: '1.0', id: 'c', documentType: 'fragment', node: { type: 'Z' } },
  });

  const out = await resolveScreenRefs({ schema, loader, maxDepth: 1 });
  assert.ok(out.errors.some((e) => e.message.includes('maxDepth')));
});
