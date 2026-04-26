import test from 'node:test';
import assert from 'node:assert/strict';
import { Database } from '../dist/store/database.js';
import { GatewayStore } from '../dist/store/gateway-store.js';

test('gateway store persists display name and online metadata', () => {
  const db = new Database(':memory:');
  const store = new GatewayStore(db);

  store.upsertRuntime({
    gateway_id: 'hermes',
    display_name: 'Hermes',
    gateway_type: 'hermes',
    status: 'online',
    capabilities: ['chat', 'tasks', 'skills', 'models'],
    last_connected_at: 100,
    last_seen_at: 100,
  });
  store.rename('hermes', 'Personal Hermes');

  const item = store.get('hermes');
  assert.equal(item.display_name, 'Personal Hermes');
  assert.equal(item.gateway_type, 'hermes');
  assert.equal(item.status, 'online');
  assert.deepEqual(item.capabilities, ['chat', 'tasks', 'skills', 'models']);
  db.close();
});

test('gateway store deletes rows absent from server snapshot', () => {
  const db = new Database(':memory:');
  const store = new GatewayStore(db);

  store.upsertRuntime({
    gateway_id: 'old',
    display_name: 'Old Gateway',
    gateway_type: 'hermes',
    status: 'disconnected',
    capabilities: ['chat'],
    last_connected_at: null,
    last_seen_at: null,
  });
  store.deleteMissing(['hermes']);

  assert.equal(store.get('old'), null);
  db.close();
});
