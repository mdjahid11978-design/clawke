const test = require('node:test');
const assert = require('node:assert/strict');
const { buildApnsPayload, PushService } = require('../dist/services/push-service');

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
