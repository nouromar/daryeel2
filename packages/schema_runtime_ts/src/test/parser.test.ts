import test from 'node:test';
import assert from 'node:assert/strict';

import { parseFragmentSchema, parseScreenSchema } from '../schema/schema_parser.js';

test('parseScreenSchema parses minimal valid document', () => {
  const parsed = parseScreenSchema({
    schemaVersion: '1.0',
    id: 'customer_home',
    documentType: 'screen',
    product: 'customer_app',
    themeId: 'customer-default',
    root: {
      type: 'ScreenTemplate',
      slots: {
        body: [{ ref: 'section:welcome' }],
      },
    },
    actions: {
      open: { type: 'navigate', route: 'schema.service' },
    },
  });

  assert.equal(parsed.value?.id, 'customer_home');
  assert.equal(parsed.errors.length, 0);
  assert.equal(parsed.value?.root.type, 'ScreenTemplate');
  assert.equal(parsed.value?.root.slots.body?.length, 1);
});

test('parseScreenSchema parses extended ActionDefinition fields', () => {
  const parsed = parseScreenSchema({
    schemaVersion: '1.0',
    id: 'customer_home',
    documentType: 'screen',
    product: 'customer_app',
    themeId: 'customer-default',
    root: { type: 'InfoCard' },
    actions: {
      track: {
        type: 'track_event',
        eventName: 'cart_add',
        eventProperties: { sku: 'abc', qty: 2, ok: true },
        value: { any: 'json' },
      },
    },
  });

  assert.equal(parsed.errors.length, 0);
  assert.equal(parsed.value?.actions.track?.type, 'track_event');
  assert.equal(parsed.value?.actions.track?.eventName, 'cart_add');
  assert.equal((parsed.value?.actions.track?.eventProperties as any)?.sku, 'abc');
  assert.equal((parsed.value?.actions.track?.eventProperties as any)?.qty, 2);
});

test('parseFragmentSchema enforces documentType=fragment', () => {
  const parsed = parseFragmentSchema({
    schemaVersion: '1.0',
    id: 'section:welcome',
    documentType: 'screen',
    node: { type: 'InfoCard' },
  });

  assert.equal(parsed.value, null);
  assert.ok(parsed.errors.some((e) => e.path === 'documentType'));
});
