const test = require('node:test');
const assert = require('node:assert/strict');

test('gateway model and skill query timeout is one minute', async () => {
  const listener = require('../dist/upstream/gateway-listener.js');

  assert.equal(listener.GATEWAY_QUERY_TIMEOUT_MS, 60_000);
});
