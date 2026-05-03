const test = require('node:test');
const assert = require('node:assert/strict');
const { Database } = require('../dist/store/database');
const { PushDeviceStore } = require('../dist/store/push-device-store');

test('push device store upserts APNs token and lists enabled devices', () => {
  const db = new Database(':memory:');
  const store = new PushDeviceStore(db);

  store.upsert({
    deviceId: 'ios-device-1',
    userId: 'local',
    platform: 'ios',
    pushProvider: 'apns',
    deviceToken: 'old-token',
    appVersion: '1.0.0',
  });
  store.upsert({
    deviceId: 'ios-device-1',
    userId: 'local',
    platform: 'ios',
    pushProvider: 'apns',
    deviceToken: 'new-token',
    appVersion: '1.0.1',
  });

  const enabled = store.listEnabled();
  assert.equal(enabled.length, 1);
  assert.equal(enabled[0].deviceId, 'ios-device-1');
  assert.equal(enabled[0].deviceToken, 'new-token');
  assert.equal(enabled[0].appVersion, '1.0.1');
  assert.equal(enabled[0].enabled, true);

  db.close();
});

test('push device store disables a registered APNs token', () => {
  const db = new Database(':memory:');
  const store = new PushDeviceStore(db);

  store.upsert({
    deviceId: 'ios-device-1',
    userId: 'local',
    platform: 'ios',
    pushProvider: 'apns',
    deviceToken: 'token',
  });

  assert.equal(store.disable('ios-device-1', 'apns'), true);
  assert.equal(store.listEnabled().length, 0);
  assert.equal(store.get('ios-device-1', 'apns')?.enabled, false);

  db.close();
});
