const assert = require('node:assert/strict');
const test = require('node:test');

const {
  DOWNLOAD_URL,
  RELEASES_URL,
  formatClientInstallBanner,
} = require('../dist/client-install-banner');

test('client install banner is boxed and highlights links when color is enabled', () => {
  const output = formatClientInstallBanner(true).join('\n');

  assert.match(output, /╔════════════════════════════════════════════════════╗/);
  assert.match(output, /Clawke Server is ready/);
  assert.match(output, /Install Clawke Client to connect/);
  assert.match(output, /Open App Store on your device and search "Clawke"/);
  assert.doesNotMatch(output, /apps\.apple\.com/);
  assert.match(output, new RegExp(`\\x1b\\[1m\\x1b\\[33m${DOWNLOAD_URL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\x1b\\[0m`));
  assert.match(output, new RegExp(`\\x1b\\[1m\\x1b\\[33m${RELEASES_URL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\x1b\\[0m`));
});

test('client install banner stays plain when color is disabled', () => {
  const lines = formatClientInstallBanner(false);
  const output = lines.join('\n');

  assert.doesNotMatch(output, /\x1b\[/);
  assert.equal([...lines[1]].length, [...lines[2]].length);
  assert.equal([...lines[1]].length, [...lines[3]].length);
  assert.equal([...lines[1]].length, [...lines[4]].length);
  assert.match(output, /iOS\/iPadOS:/);
  assert.match(output, /Download:/);
  assert.match(output, /Other platforms:/);
});
