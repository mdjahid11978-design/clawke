const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..', '..');
const runner = readFileSync(
  join(root, 'test', 'ui-e2e', 'tools', 'runner.mjs'),
  'utf8',
);

test('UI E2E human report displays result status instead of demo fail flag', () => {
  assert.doesNotMatch(runner, /Demo Fail/);
  assert.doesNotMatch(runner, /demo_fail:/);
  assert.match(runner, /function reportStatus\(ok\)/);
  assert.match(runner, /测试结果/);
  assert.match(runner, /- 测试结果: status: \$\{statusValue\}/);
  assert.match(runner, /status: \$\{escapeHtml\(statusValue\)\}/);
});
