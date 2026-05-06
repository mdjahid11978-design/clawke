const assert = require('node:assert/strict');
const test = require('node:test');

const {
  formatAuthBanner,
  formatAuthWaitingLine,
  shouldUseColor,
} = require('../dist/tunnel/device-auth');

test('device auth banner uses cyan and yellow when color is enabled', () => {
  const output = formatAuthBanner('https://clawke.ai/clawke/deviceAuth.htm?key=test', 600, true).join('\n');

  assert.match(output, /\x1b\[1m\x1b\[36m/);
  assert.match(output, /\x1b\[1m\x1b\[33m  https:\/\/clawke\.ai\/clawke\/deviceAuth\.htm\?key=test\x1b\[0m/);
  assert.match(formatAuthWaitingLine('  ⏳ Waiting for authorization... (expires in 10:00)', true), /^\x1b\[33m.*\x1b\[0m$/);
});

test('device auth banner stays plain when color is disabled', () => {
  const output = formatAuthBanner('https://clawke.ai/clawke/deviceAuth.htm?key=test', 600, false).join('\n');

  assert.doesNotMatch(output, /\x1b\[/);
  assert.equal(formatAuthWaitingLine('  ⏳ Waiting for authorization... (expires in 10:00)', false), '  ⏳ Waiting for authorization... (expires in 10:00)');
});

test('device auth color support respects TTY and NO_COLOR', () => {
  const oldNoColor = process.env.NO_COLOR;
  delete process.env.NO_COLOR;
  assert.equal(shouldUseColor({ isTTY: true }), true);
  assert.equal(shouldUseColor({ isTTY: false }), false);

  process.env.NO_COLOR = '1';
  assert.equal(shouldUseColor({ isTTY: true }), false);

  process.env.NO_COLOR = '';
  assert.equal(shouldUseColor({ isTTY: true }), false);

  if (oldNoColor === undefined) {
    delete process.env.NO_COLOR;
  } else {
    process.env.NO_COLOR = oldNoColor;
  }
});
