const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repoRoot = path.resolve(__dirname, '..', '..');

test('clawke server start waits for server ready before starting gateways', () => {
  const cliSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'cli', 'clawke.ts'), 'utf8');
  const serverStartBody = cliSource.match(/async function serverStart\(\): Promise<void> \{([\s\S]*?)\n\}/);

  assert.ok(serverStartBody, 'serverStart() not found');
  assert.match(serverStartBody[1], /const \{ startClawkeServer \} = await import\('\.\.\/index\.js'\)/);
  assert.match(serverStartBody[1], /await startClawkeServer\(\)/);
  assert.match(serverStartBody[1], /await startGateways\(\)/);
  assert.doesNotMatch(serverStartBody[1], /setTimeout/);
});

test('server index exports explicit startup function and keeps standalone startup guarded', () => {
  const indexSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'index.ts'), 'utf8');

  assert.match(indexSource, /export async function startClawkeServer\(\)/);
  assert.match(indexSource, /function isDirectRun\(entryPath: string \| undefined\): boolean/);
  assert.match(indexSource, /if \(isDirectRun\(process\.argv\[1\]\)\)/);
  assert.doesNotMatch(indexSource, /^main\(\)\.catch/m);
});
