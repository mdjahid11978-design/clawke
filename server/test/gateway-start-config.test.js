const test = require('node:test');
const assert = require('node:assert/strict');

const { resolveGatewayStartShell } = require('../dist/cli/gateway-start-config.js');

test('resolveGatewayStartShell returns trimmed shell command', () => {
  assert.equal(
    resolveGatewayStartShell({ start_shell: '  python run.py  ' }),
    'python run.py',
  );
});

test('resolveGatewayStartShell skips externally managed gateways without start_shell', () => {
  assert.equal(resolveGatewayStartShell({ id: 'OpenClaw' }), null);
  assert.equal(resolveGatewayStartShell({ id: 'nanobot', start_shell: '' }), null);
  assert.equal(resolveGatewayStartShell({ id: 'bad', start_shell: 123 }), null);
});
