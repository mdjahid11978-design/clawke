const test = require('node:test');
const assert = require('node:assert/strict');

test('enableControlUiInsecureAuthForClawke creates gateway control UI config', async () => {
  const { enableControlUiInsecureAuthForClawke } = await import(
    '../dist/cli/openclaw-gateway-installer.js'
  );
  const config = {};

  const changed = enableControlUiInsecureAuthForClawke(config);

  assert.equal(changed, true);
  assert.deepEqual(config, {
    gateway: {
      controlUi: {
        allowInsecureAuth: true,
      },
    },
  });
});

test('enableControlUiInsecureAuthForClawke preserves existing control UI config', async () => {
  const { enableControlUiInsecureAuthForClawke } = await import(
    '../dist/cli/openclaw-gateway-installer.js'
  );
  const config = {
    gateway: {
      controlUi: {
        basePath: '/openclaw',
        allowInsecureAuth: false,
      },
    },
  };

  const changed = enableControlUiInsecureAuthForClawke(config);

  assert.equal(changed, true);
  assert.deepEqual(config.gateway.controlUi, {
    basePath: '/openclaw',
    allowInsecureAuth: true,
  });
});

test('enableControlUiInsecureAuthForClawke reports unchanged when already enabled', async () => {
  const { enableControlUiInsecureAuthForClawke } = await import(
    '../dist/cli/openclaw-gateway-installer.js'
  );
  const config = {
    gateway: {
      controlUi: {
        allowInsecureAuth: true,
      },
    },
  };

  const changed = enableControlUiInsecureAuthForClawke(config);

  assert.equal(changed, false);
  assert.equal(config.gateway.controlUi.allowInsecureAuth, true);
});
