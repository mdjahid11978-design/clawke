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
