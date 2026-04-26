import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

test('registerGatewayInClawkeConfig creates and updates gateway entries', async () => {
  const { registerGatewayInClawkeConfig } = await import('../dist/cli/clawke-config-writer.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-config-writer-'));
  const configPath = path.join(dir, 'clawke.json');

  registerGatewayInClawkeConfig({
    configPath,
    gatewayType: 'openclaw',
    gatewayId: 'OpenClaw',
  });
  registerGatewayInClawkeConfig({
    configPath,
    gatewayType: 'openclaw',
    gatewayId: 'OpenClaw',
  });
  registerGatewayInClawkeConfig({
    configPath,
    gatewayType: 'hermes',
    gatewayId: 'hermes',
    values: { start_shell: 'python run.py' },
  });

  const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

  assert.deepEqual(config.gateways.openclaw, [{ id: 'OpenClaw' }]);
  assert.deepEqual(config.gateways.hermes, [
    { id: 'hermes', start_shell: 'python run.py' },
  ]);
});
