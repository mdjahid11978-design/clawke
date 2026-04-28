const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const {
  initConfigRoutes,
  listModels,
  getModels,
} = require('../dist/routes/config-routes');
const { Database, GatewayModelCacheStore } = require('../dist/store');

function createStore() {
  const db = new Database(':memory:');
  const modelCacheStore = new GatewayModelCacheStore(db);
  return { db, modelCacheStore };
}

async function getJson(path) {
  const url = new URL(path, 'http://127.0.0.1');
  const handler = url.pathname === '/api/models'
    ? listModels
    : url.pathname === '/api/config/models'
      ? getModels
      : null;

  if (!handler) {
    return { status: 404, body: { error: 'not_found' } };
  }

  const routeReq = { query: Object.fromEntries(url.searchParams.entries()) };
  const routeRes = {
    statusCode: 200,
    payload: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.payload = payload;
      return this;
    },
  };
  await handler(routeReq, routeRes);
  return { status: routeRes.statusCode, body: routeRes.payload };
}

describe('Model routes gateway resource endpoint', () => {
  let activeDb;

  function configureRoutes({
    modelCacheStore,
    queryModels,
  } = {}) {
    initConfigRoutes({
      configStore: { get: () => null, set: () => {}, delete: () => {} },
      modelCacheStore,
      queryModels: queryModels || (async () => []),
      querySkills: async () => [],
    });
  }

  beforeEach(() => {
    if (activeDb) {
      activeDb.close();
      activeDb = undefined;
    }
    configureRoutes();
  });

  afterEach(() => {
    if (activeDb) {
      activeDb.close();
      activeDb = undefined;
    }
  });

  it('GET /api/models queries models by gateway_id and stores the result in DB', async () => {
    const { db, modelCacheStore } = createStore();
    activeDb = db;
    let calls = 0;
    configureRoutes({
      modelCacheStore,
      queryModels: async (gatewayId) => {
        calls += 1;
        assert.equal(gatewayId, 'hermes');
        return [{
          model_id: `hermes/model-${calls}`,
          id: `model-${calls}`,
          provider: 'hermes',
          display_name: `Model ${calls}`,
          name: `Model ${calls}`,
          context_window: 1000,
          reasoning: true,
          input: ['text'],
        }];
      },
    });

    const first = await getJson('/api/models?gateway_id=hermes');
    assert.equal(first.status, 200);
    assert.deepEqual(first.body.models, [{
      model_id: 'hermes/model-1',
      id: 'model-1',
      provider: 'hermes',
      display_name: 'Model 1',
      name: 'Model 1',
      context_window: 1000,
      reasoning: true,
      input: ['text'],
    }]);
    assert.deepEqual(modelCacheStore.getGatewayModels('hermes'), [{
      model_id: 'hermes/model-1',
      id: 'model-1',
      provider: 'hermes',
      display_name: 'Model 1',
      name: 'Model 1',
      context_window: 1000,
      reasoning: true,
      input: ['text'],
    }]);

    const second = await getJson('/api/models?gateway_id=hermes');
    assert.equal(second.status, 200);
    assert.deepEqual(second.body.models, [{
      model_id: 'hermes/model-1',
      id: 'model-1',
      provider: 'hermes',
      display_name: 'Model 1',
      name: 'Model 1',
      context_window: 1000,
      reasoning: true,
      input: ['text'],
    }]);
    assert.equal(calls, 1);
  });

  it('GET /api/models refresh=1 bypasses persisted model cache', async () => {
    const { db, modelCacheStore } = createStore();
    activeDb = db;
    let calls = 0;
    configureRoutes({
      modelCacheStore,
      queryModels: async () => {
        calls += 1;
        return [{
          model_id: `openclaw/model-${calls}`,
          id: `model-${calls}`,
          provider: 'openclaw',
          display_name: `Model ${calls}`,
        }];
      },
    });

    await getJson('/api/models?gateway_id=hermes');

    const refreshed = await getJson('/api/models?gateway_id=hermes&refresh=1');
    assert.equal(refreshed.status, 200);
    assert.deepEqual(refreshed.body.models, [{
      model_id: 'openclaw/model-2',
      id: 'model-2',
      provider: 'openclaw',
      display_name: 'Model 2',
    }]);
    assert.equal(calls, 2);
    assert.deepEqual(modelCacheStore.getGatewayModels('hermes'), [{
      model_id: 'openclaw/model-2',
      id: 'model-2',
      provider: 'openclaw',
      display_name: 'Model 2',
    }]);
  });

  it('GET /api/models refresh=1 returns persisted cache when gateway refresh fails', async () => {
    const { db, modelCacheStore } = createStore();
    activeDb = db;
    modelCacheStore.replaceGatewayModels('OpenClaw', ['openclaw/cached-model']);
    configureRoutes({
      modelCacheStore,
      queryModels: async () => {
        throw new Error('gateway unavailable');
      },
    });

    const response = await getJson('/api/models?gateway_id=OpenClaw&refresh=1');
    assert.equal(response.status, 200);
    assert.deepEqual(response.body.models, [{
      model_id: 'openclaw/cached-model',
      id: 'cached-model',
      provider: 'openclaw',
      display_name: 'openclaw/cached-model',
    }]);
  });

  it('GET /api/models refresh=1 does not overwrite persisted cache with an empty gateway result', async () => {
    const { db, modelCacheStore } = createStore();
    activeDb = db;
    modelCacheStore.replaceGatewayModels('OpenClaw', ['openclaw/cached-model']);
    configureRoutes({
      modelCacheStore,
      queryModels: async () => [],
    });

    const response = await getJson('/api/models?gateway_id=OpenClaw&refresh=1');
    assert.equal(response.status, 200);
    assert.deepEqual(response.body.models, [{
      model_id: 'openclaw/cached-model',
      id: 'cached-model',
      provider: 'openclaw',
      display_name: 'openclaw/cached-model',
    }]);
    assert.deepEqual(modelCacheStore.getGatewayModels('OpenClaw'), [{
      model_id: 'openclaw/cached-model',
      id: 'cached-model',
      provider: 'openclaw',
      display_name: 'openclaw/cached-model',
    }]);
  });

  it('GET /api/models returns persisted model cache before querying gateway', async () => {
    const { db, modelCacheStore } = createStore();
    activeDb = db;
    modelCacheStore.replaceGatewayModels('OpenClaw', ['openclaw/cached-model']);
    let calls = 0;
    configureRoutes({
      modelCacheStore,
      queryModels: async () => {
        calls += 1;
        return [{
          model_id: 'openclaw/fresh-model',
          id: 'fresh-model',
          provider: 'openclaw',
          display_name: 'Fresh Model',
        }];
      },
    });

    const response = await getJson('/api/models?gateway_id=OpenClaw');
    assert.equal(response.status, 200);
    assert.deepEqual(response.body.models, [{
      model_id: 'openclaw/cached-model',
      id: 'cached-model',
      provider: 'openclaw',
      display_name: 'openclaw/cached-model',
    }]);
    assert.equal(calls, 0);
  });

  it('GET /api/models keeps legacy string gateway responses compatible', async () => {
    const { db, modelCacheStore } = createStore();
    activeDb = db;
    configureRoutes({
      modelCacheStore,
      queryModels: async () => ['openclaw/string-model'],
    });

    const response = await getJson('/api/models?gateway_id=OpenClaw&refresh=1');
    assert.equal(response.status, 200);
    assert.deepEqual(response.body.models, [{
      model_id: 'openclaw/string-model',
      id: 'string-model',
      provider: 'openclaw',
      display_name: 'openclaw/string-model',
    }]);
  });

  it('deprecated GET /api/config/models remains compatible with account_id and refresh=true', async () => {
    const { db, modelCacheStore } = createStore();
    activeDb = db;
    let calls = 0;
    configureRoutes({
      modelCacheStore,
      queryModels: async (gatewayId) => {
        calls += 1;
        assert.equal(gatewayId, 'hermes');
        return [{
          model_id: `hermes/claude-sonnet-${calls}`,
          id: `claude-sonnet-${calls}`,
          provider: 'hermes',
          display_name: `Claude Sonnet ${calls}`,
        }];
      },
    });

    await getJson('/api/config/models?account_id=hermes');

    const response = await getJson('/api/config/models?account_id=hermes&refresh=true');
    assert.equal(response.status, 200);
    assert.deepEqual(response.body.models, [{
      model_id: 'hermes/claude-sonnet-2',
      id: 'claude-sonnet-2',
      provider: 'hermes',
      display_name: 'Claude Sonnet 2',
    }]);
    assert.equal(calls, 2);
  });
});
