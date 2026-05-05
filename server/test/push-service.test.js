const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildApnsPayload,
  createCloudPushClient,
  DEFAULT_CLOUD_PUSH_TIMEOUT_MS,
  PushService,
} = require('../dist/services/push-service');

test('buildApnsPayload keeps APNs payload lightweight', () => {
  const payload = buildApnsPayload({
    conversationId: 'conv_1',
    messageId: 'msg_1',
    gatewayId: 'hermes',
    seq: 42,
    title: 'New message',
    body: 'Open Clawke to sync.',
    badge: 3,
  });

  assert.deepEqual(payload.aps.alert, {
    title: 'New message',
    body: 'Open Clawke to sync.',
  });
  assert.equal(payload.aps.badge, 3);
  assert.equal(payload.aps.sound, 'default');
  assert.equal(payload.aps['content-available'], undefined);
  assert.equal(payload.conversation_id, 'conv_1');
  assert.equal(payload.message_id, 'msg_1');
  assert.equal(payload.gateway_id, 'hermes');
  assert.equal(payload.seq, 42);
  assert.equal(payload.content, undefined);
});

test('PushService sends one APNs notification per enabled device', async () => {
  const sent = [];
  const service = new PushService({
    listDevices: () => [
      {
        deviceId: 'ios-1',
        userId: 'local',
        platform: 'ios',
        pushProvider: 'apns',
        deviceToken: 'token-1',
        enabled: true,
        createdAt: 1,
        updatedAt: 1,
      },
      {
        deviceId: 'ios-2',
        userId: 'local',
        platform: 'ios',
        pushProvider: 'apns',
        deviceToken: 'token-2',
        enabled: true,
        createdAt: 1,
        updatedAt: 1,
      },
    ],
    apnsProvider: {
      send: async (device, payload) => {
        sent.push({ device, payload });
        return { ok: true };
      },
    },
  });

  const result = await service.notifyMessage({
    conversationId: 'conv_1',
    messageId: 'msg_1',
    gatewayId: 'hermes',
    seq: 42,
  });

  assert.equal(result.attempted, 2);
  assert.equal(result.sent, 2);
  assert.equal(result.failed, 0);
  assert.deepEqual(result.details.map((item) => ({
    deviceId: item.deviceId,
    platform: item.platform,
    ok: item.ok,
  })), [
    { deviceId: 'ios-1', platform: 'ios', ok: true },
    { deviceId: 'ios-2', platform: 'ios', ok: true },
  ]);
  assert.equal(sent.length, 2);
  assert.equal(sent[0].payload.conversation_id, 'conv_1');
  assert.equal(sent[1].device.deviceToken, 'token-2');
});

test('PushService pushes final message through cloud push API once', async () => {
  const calls = [];
  const service = new PushService({
    cloudClient: {
      pushMessage: async (message) => {
        calls.push(message);
        return { attempted: 2, sent: 2, failed: 0, details: [] };
      },
    },
  });

  const result = await service.notifyMessage({
    conversationId: 'conv_1',
    messageId: 'msg_1',
    gatewayId: 'hermes',
    seq: 42,
    title: 'Hermes',
    body: 'done',
    badge: 3,
  });

  assert.deepEqual(calls, [{
    conversationId: 'conv_1',
    messageId: 'msg_1',
    gatewayId: 'hermes',
    seq: 42,
    title: 'Hermes',
    body: 'done',
    badge: 3,
  }]);
  assert.equal(result.sent, 2);
  assert.equal(result.failed, 0);
});

test('PushService logs cloud push delivery counts', async () => {
  const logs = [];
  const originalLog = console.log;
  console.log = (message) => logs.push(String(message));

  try {
    const service = new PushService({
      cloudClient: {
        pushMessage: async () => ({ attempted: 3, sent: 3, failed: 0, details: [] }),
      },
    });

    await service.notifyMessage({
      conversationId: 'conv_1',
      messageId: 'smsg_1',
      gatewayId: 'hermes',
      seq: 42,
      title: 'Hermes',
      body: 'done',
    });

    assert.equal(logs.length, 1);
    assert.match(logs[0], /Cloud push result/);
    assert.match(logs[0], /message=smsg_1/);
    assert.match(logs[0], /gateway=hermes/);
    assert.match(logs[0], /attempted=3/);
    assert.match(logs[0], /sent=3/);
    assert.match(logs[0], /failed=0/);
  } finally {
    console.log = originalLog;
  }
});

test('createCloudPushClient posts pushMessage to configured API base', async () => {
  const calls = [];
  const client = createCloudPushClient({
    apiBaseUrl: 'https://local.clawke.ai/',
    relayToken: 'clk_testtoken',
    fetchImpl: async (url, options) => {
      calls.push({
        url: String(url),
        method: options.method,
        headers: options.headers,
        body: JSON.parse(options.body),
      });
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({
          success: true,
          value: { targetCount: 1, successCount: 1, failureCount: 0 },
        }),
      };
    },
  });

  assert.ok(client);
  const result = await client.pushMessage({
    conversationId: 'conv_1',
    messageId: 'msg_1',
    gatewayId: 'hermes',
    seq: 42,
    title: 'Hermes',
    body: 'done',
  });

  assert.equal(result.attempted, 1);
  assert.equal(result.sent, 1);
  assert.equal(result.failed, 0);
  assert.equal(calls.length, 1);
  assert.equal(
    calls[0].url,
    'https://local.clawke.ai/api/clawke/push/pushMessage.json',
  );
  assert.equal(calls[0].headers.Authorization, 'Bearer clk_testtoken');
  assert.equal(calls[0].body.conversationId, 'conv_1');
  assert.equal(calls[0].body.gatewayId, 'hermes');
});

test('createCloudPushClient defaults to official API and skips without token', () => {
  assert.equal(createCloudPushClient({ relayToken: '' }), null);
  const client = createCloudPushClient({
    relayToken: 'clk_testtoken',
    fetchImpl: async () => {
      throw new Error('not called');
    },
  });
  assert.ok(client);
  assert.equal(client.baseUrl, 'https://api.clawke.ai');
  assert.equal(client.timeoutMs, DEFAULT_CLOUD_PUSH_TIMEOUT_MS);
  assert.ok(client.timeoutMs >= 15000);
});

test('createCloudPushClient proxies register and unregister device calls', async () => {
  const calls = [];
  const client = createCloudPushClient({
    apiBaseUrl: 'https://local.clawke.ai',
    relayToken: 'clk_testtoken',
    fetchImpl: async (url, options) => {
      calls.push({
        url: String(url),
        headers: options.headers,
        body: JSON.parse(options.body),
      });
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ success: true }),
      };
    },
  });

  assert.ok(client);
  assert.deepEqual(
    await client.registerDevice({
      deviceId: 'device-1',
      platform: 'ios',
      pushProvider: 'apns',
      deviceToken: 'token-1',
      appBundleId: 'ai.clawke.app',
      appVersion: '1.0.0',
    }),
    { ok: true, status: 200 },
  );
  assert.deepEqual(
    await client.unregisterDevice({
      deviceId: 'device-1',
      pushProvider: 'apns',
    }),
    { ok: true, status: 200 },
  );

  assert.equal(
    calls[0].url,
    'https://local.clawke.ai/api/clawke/push/registerDevice.json',
  );
  assert.equal(calls[0].headers.Authorization, 'Bearer clk_testtoken');
  assert.equal(calls[0].body.deviceId, 'device-1');
  assert.equal(calls[0].body.deviceToken, 'token-1');
  assert.equal(
    calls[1].url,
    'https://local.clawke.ai/api/clawke/push/unregisterDevice.json',
  );
  assert.deepEqual(calls[1].body, {
    deviceId: 'device-1',
    pushProvider: 'apns',
  });
});

test('PushService keeps iOS audible and sends macOS silently', async () => {
  const sent = [];
  const service = new PushService({
    listDevices: () => [
      {
        deviceId: 'ios-1',
        userId: 'local',
        platform: 'ios',
        pushProvider: 'apns',
        deviceToken: 'ios-token',
        enabled: true,
        createdAt: 1,
        updatedAt: 1,
      },
      {
        deviceId: 'mac-1',
        userId: 'local',
        platform: 'macos',
        pushProvider: 'apns',
        deviceToken: 'mac-token',
        enabled: true,
        createdAt: 1,
        updatedAt: 1,
      },
    ],
    apnsProvider: {
      send: async (device, payload) => {
        sent.push({ device, payload });
        return { ok: true };
      },
    },
  });

  await service.notifyMessage({
    conversationId: 'conv_1',
    messageId: 'msg_1',
    gatewayId: 'hermes',
    seq: 42,
  });

  assert.equal(sent.find((item) => item.device.platform === 'ios').payload.aps.sound, 'default');
  assert.equal(sent.find((item) => item.device.platform === 'macos').payload.aps.sound, undefined);
});
