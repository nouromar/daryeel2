import test from 'node:test';
import assert from 'node:assert/strict';

import { makeComponentNode } from '../index.js';

test('package exports work', () => {
  const node = makeComponentNode({
    type: 'InfoCard',
    props: { title: 'Hello' },
    slots: {},
    actions: {},
  });

  assert.equal(node.kind, 'component');
  assert.equal(node.type, 'InfoCard');
});
