const test = require('node:test');
const assert = require('node:assert/strict');

test('registerPushDevice validates required APNs fields', async () => {
  const routes = require('../dist/routes/push-routes');
  routes.initPushRoutes({
    deviceStore: {
      upsert: () => {
        throw new Error('upsert should not be called');
      },
    },
  });

  const res = fakeRes();
  await routes.registerPushDevice(fakeReq({ body: { platform: 'ios' } }), res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'validation_error');
});

test('registerPushDevice stores APNs token without echoing token', async () => {
  const writes = [];
  const routes = require('../dist/routes/push-routes');
  routes.initPushRoutes({
    deviceStore: {
      upsert: (device) => {
        writes.push(device);
        return { ...device, enabled: true, createdAt: 100, updatedAt: 101 };
      },
    },
  });

  const res = fakeRes();
  await routes.registerPushDevice(fakeReq({
    body: {
      device_id: 'ios-device-1',
      user_id: 'user-1',
      platform: 'ios',
      push_provider: 'apns',
      device_token: 'secret-token',
      app_version: '1.0.0',
    },
  }), res);

  assert.equal(res.statusCode, 201);
  assert.deepEqual(writes, [{
    deviceId: 'ios-device-1',
    userId: 'user-1',
    platform: 'ios',
    pushProvider: 'apns',
    deviceToken: 'secret-token',
    appVersion: '1.0.0',
  }]);
  assert.equal(res.body.device.device_id, 'ios-device-1');
  assert.equal(res.body.device.device_token, undefined);
});

test('registerPushDevice proxies APNs token to cloud API when configured', async () => {
  const cloudCalls = [];
  const routes = require('../dist/routes/push-routes');
  routes.initPushRoutes({
    deviceStore: {
      upsert: () => {
        throw new Error('local store should not be called');
      },
    },
    cloudClient: {
      registerDevice: async (device) => {
        cloudCalls.push(device);
        return { ok: true, status: 200 };
      },
    },
  });

  const res = fakeRes();
  await routes.registerPushDevice(fakeReq({
    body: {
      device_id: 'ios-device-1',
      platform: 'ios',
      push_provider: 'apns',
      device_token: 'secret-token',
      app_bundle_id: 'ai.clawke.app',
      app_version: '1.0.0',
    },
  }), res);

  assert.equal(res.statusCode, 201);
  assert.deepEqual(cloudCalls, [{
    deviceId: 'ios-device-1',
    platform: 'ios',
    pushProvider: 'apns',
    deviceToken: 'secret-token',
    appBundleId: 'ai.clawke.app',
    appVersion: '1.0.0',
  }]);
  assert.equal(res.body.device.device_id, 'ios-device-1');
  assert.equal(res.body.device.device_token, undefined);
});

test('registerPushDevice proxies Android FCM token to cloud API when configured', async () => {
  const cloudCalls = [];
  const routes = require('../dist/routes/push-routes');
  routes.initPushRoutes({
    deviceStore: {
      upsert: () => {
        throw new Error('local store should not be called');
      },
    },
    cloudClient: {
      registerDevice: async (device) => {
        cloudCalls.push(device);
        return { ok: true, status: 200 };
      },
    },
  });

  const res = fakeRes();
  await routes.registerPushDevice(fakeReq({
    body: {
      device_id: 'android-device-1',
      platform: 'android',
      push_provider: 'fcm',
      device_token: 'secret-fcm-token',
      app_bundle_id: 'ai.clawke.app',
      app_version: '1.0.0',
    },
  }), res);

  assert.equal(res.statusCode, 201);
  assert.deepEqual(cloudCalls, [{
    deviceId: 'android-device-1',
    platform: 'android',
    pushProvider: 'fcm',
    deviceToken: 'secret-fcm-token',
    appBundleId: 'ai.clawke.app',
    appVersion: '1.0.0',
  }]);
  assert.equal(res.body.device.device_id, 'android-device-1');
  assert.equal(res.body.device.device_token, undefined);
});

test('registerPushDevice logs cloud API failure details without token', async () => {
  const logs = [];
  const originalWarn = console.warn;
  console.warn = (message) => logs.push(String(message));

  try {
    const routes = require('../dist/routes/push-routes');
    routes.initPushRoutes({
      deviceStore: {
        upsert: () => {
          throw new Error('local store should not be called');
        },
      },
      cloudClient: {
        registerDevice: async () => ({
          ok: false,
          status: 401,
          error: 'LOGIN_FAILED',
        }),
      },
    });

    const res = fakeRes();
    await routes.registerPushDevice(fakeReq({
      body: {
        device_id: 'android-device-1',
        platform: 'android',
        push_provider: 'fcm',
        device_token: 'secret-fcm-token',
        app_bundle_id: 'ai.clawke.app',
        app_version: '1.0.0',
      },
    }), res);

    assert.equal(res.statusCode, 502);
    assert.equal(res.body.error, 'push_api_failed');
    assert.equal(res.body.message, 'LOGIN_FAILED');
    assert.equal(logs.length, 1);
    assert.match(logs[0], /registerDevice failed/);
    assert.match(logs[0], /status=401/);
    assert.match(logs[0], /error=LOGIN_FAILED/);
    assert.match(logs[0], /platform=android/);
    assert.match(logs[0], /provider=fcm/);
    assert.match(logs[0], /device=android-device-1/);
    assert.match(logs[0], /token_len=16/);
    assert.doesNotMatch(logs[0], /secret-fcm-token/);
  } finally {
    console.warn = originalWarn;
  }
});

test('disablePushDevice proxies unregister to cloud API when configured', async () => {
  const cloudCalls = [];
  const routes = require('../dist/routes/push-routes');
  routes.initPushRoutes({
    deviceStore: {},
    cloudClient: {
      unregisterDevice: async (device) => {
        cloudCalls.push(device);
        return { ok: true, status: 200 };
      },
    },
  });

  const res = fakeRes();
  await routes.disablePushDevice(fakeReq({
    params: { deviceId: 'ios-device-1' },
    query: { push_provider: 'apns' },
  }), res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { ok: true });
  assert.deepEqual(cloudCalls, [{
    deviceId: 'ios-device-1',
    pushProvider: 'apns',
  }]);
});

test('sendTestPush dispatches through push service', async () => {
  const calls = [];
  const routes = require('../dist/routes/push-routes');
  routes.initPushRoutes({
    deviceStore: {
      upsert: () => {},
    },
    pushService: {
      notifyMessage: async (message) => {
        calls.push(message);
        return { attempted: 1, sent: 1, failed: 0 };
      },
    },
  });

  const res = fakeRes();
  await routes.sendTestPush(fakeReq({
    body: {
      conversation_id: 'conv_1',
      message_id: 'msg_1',
      gateway_id: 'hermes',
      seq: 42,
      badge: 7,
    },
  }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].conversationId, 'conv_1');
  assert.equal(calls[0].messageId, 'msg_1');
  assert.equal(calls[0].badge, 7);
  assert.equal(res.body.sent, 1);
});

test('sendTestPush uses gateway id and stored message content for APNs alert', async () => {
  const calls = [];
  const routes = require('../dist/routes/push-routes');
  routes.initPushRoutes({
    deviceStore: {
      upsert: () => {},
    },
    conversationStore: {
      get: (id) => (id === 'conv_1' ? { id } : null),
    },
    messageStore: {
      getById: (id) =>
        id === 'msg_1'
          ? { conversationId: 'conv_1', seq: 42, content: 'hello from stored message' }
          : null,
    },
    pushService: {
      notifyMessage: async (message) => {
        calls.push(message);
        return { attempted: 1, sent: 1, failed: 0 };
      },
    },
  });

  const res = fakeRes();
  await routes.sendTestPush(fakeReq({
    body: {
      conversation_id: 'conv_1',
      message_id: 'msg_1',
      gateway_id: 'hermes',
      seq: 42,
    },
  }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(calls[0].title, 'hermes');
  assert.equal(calls[0].body, 'hello from stored message');
});

test('sendTestPush rejects missing conversation and message mismatches when stores are available', async () => {
  const calls = [];
  const routes = require('../dist/routes/push-routes');
  routes.initPushRoutes({
    deviceStore: {
      upsert: () => {},
    },
    conversationStore: {
      get: (id) => (id === 'conv_1' ? { id } : null),
    },
    messageStore: {
      getById: (id) =>
        id === 'msg_1' ? { conversationId: 'conv_1', seq: 42 } : null,
    },
    pushService: {
      notifyMessage: async (message) => {
        calls.push(message);
        return { attempted: 1, sent: 1, failed: 0 };
      },
    },
  });

  const missingConversation = fakeRes();
  await routes.sendTestPush(fakeReq({
    body: {
      conversation_id: 'missing',
      message_id: 'msg_1',
      gateway_id: 'hermes',
      seq: 42,
    },
  }), missingConversation);
  assert.equal(missingConversation.statusCode, 404);
  assert.equal(missingConversation.body.error, 'conversation_not_found');

  const missingMessage = fakeRes();
  await routes.sendTestPush(fakeReq({
    body: {
      conversation_id: 'conv_1',
      message_id: 'missing',
      gateway_id: 'hermes',
      seq: 42,
    },
  }), missingMessage);
  assert.equal(missingMessage.statusCode, 404);
  assert.equal(missingMessage.body.error, 'message_not_found');

  const mismatchedSeq = fakeRes();
  await routes.sendTestPush(fakeReq({
    body: {
      conversation_id: 'conv_1',
      message_id: 'msg_1',
      gateway_id: 'hermes',
      seq: 99,
    },
  }), mismatchedSeq);
  assert.equal(mismatchedSeq.statusCode, 400);
  assert.equal(mismatchedSeq.body.error, 'message_seq_mismatch');
  assert.equal(calls.length, 0);
});

function fakeReq({ body = {}, params = {}, query = {} } = {}) {
  return { body, params, query };
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
