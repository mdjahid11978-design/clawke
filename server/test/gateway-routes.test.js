import test from 'node:test';
import assert from 'node:assert/strict';

test('listGateways returns configured gateways with runtime status', async () => {
  const routes = await import('../dist/routes/gateway-routes.js');
  const stored = new Map([
    ['hermes', {
      gateway_id: 'hermes',
      display_name: 'Personal Hermes',
      gateway_type: 'hermes',
      status: 'disconnected',
      capabilities: ['chat', 'tasks'],
    }],
  ]);
  routes.initGatewayRoutes({
    gatewayStore: {
      get: (id) => stored.get(id) || null,
      upsertRuntime: (item) => stored.set(item.gateway_id, item),
      rename: () => true,
      deleteMissing: () => {},
    },
    listConfiguredGateways: () => [{
      gateway_id: 'hermes',
      display_name: 'Hermes',
      gateway_type: 'hermes',
      capabilities: ['chat', 'tasks'],
    }, {
      gateway_id: 'OpenClaw',
      display_name: 'OpenClaw',
      gateway_type: 'openclaw',
      capabilities: ['chat', 'skills'],
    }],
    getConnectedGateways: () => [{
      gateway_id: 'OpenClaw',
      display_name: 'OpenClaw',
      gateway_type: 'openclaw',
      status: 'online',
      capabilities: ['chat', 'skills'],
    }],
  });

  const res = fakeRes();
  await routes.listGateways(fakeReq(), res);

  assert.equal(res.body.gateways.length, 2);
  assert.equal(res.body.gateways[0].gateway_id, 'hermes');
  assert.equal(res.body.gateways[0].display_name, 'Personal Hermes');
  assert.equal(res.body.gateways[0].status, 'disconnected');
  assert.equal(res.body.gateways[1].gateway_id, 'OpenClaw');
  assert.equal(res.body.gateways[1].status, 'online');
});

test('listGateways includes connected gateways missing from config', async () => {
  const routes = await import('../dist/routes/gateway-routes.js');
  const stored = new Map();
  routes.initGatewayRoutes({
    gatewayStore: {
      get: (id) => stored.get(id) || null,
      upsertRuntime: (item) => stored.set(item.gateway_id, item),
      rename: () => true,
      deleteMissing: () => {},
    },
    listConfiguredGateways: () => [],
    getConnectedGateways: () => [{
      gateway_id: 'OpenClaw',
      display_name: 'OpenClaw',
      gateway_type: 'openclaw',
      status: 'online',
      capabilities: ['chat', 'skills'],
    }],
  });

  const res = fakeRes();
  await routes.listGateways(fakeReq(), res);

  assert.equal(res.body.gateways.length, 1);
  assert.equal(res.body.gateways[0].gateway_id, 'OpenClaw');
  assert.equal(res.body.gateways[0].status, 'online');
});

test('renameGateway is server first and rejects empty names', async () => {
  const routes = await import('../dist/routes/gateway-routes.js');
  routes.initGatewayRoutes({
    gatewayStore: {
      get: () => ({
        gateway_id: 'hermes',
        display_name: 'Hermes',
        gateway_type: 'hermes',
        status: 'online',
        capabilities: ['chat'],
      }),
      upsertRuntime: () => {},
      rename: () => true,
      deleteMissing: () => {},
    },
    listConfiguredGateways: () => [],
    getConnectedGateways: () => [],
  });

  const res = fakeRes();
  await routes.renameGateway(fakeReq({
    params: { gatewayId: 'hermes' },
    body: { display_name: '' },
  }), res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'validation_error');
});

function fakeReq(overrides = {}) {
  return {
    params: {},
    body: {},
    query: {},
    ...overrides,
  };
}

function fakeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}
