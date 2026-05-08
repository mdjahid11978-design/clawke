const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function makeCapture() {
  let text = '';
  return {
    stream: {
      write(chunk) {
        text += String(chunk);
      },
    },
    text() {
      return text;
    },
  };
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n');
}

test('gateway update syncs configured local OpenClaw gateway without restart', async () => {
  const { runGatewayUpdate } = await import('../dist/cli/gateway-updater.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateway-update-'));
  const projectRoot = path.join(dir, 'clawke');
  const configPath = path.join(dir, 'clawke.json');
  const openclawHome = path.join(dir, '.openclaw');
  const sourceDir = path.join(projectRoot, 'gateways', 'openclaw', 'clawke');
  const targetDir = path.join(openclawHome, 'extensions', 'clawke');
  const stdout = makeCapture();
  const stderr = makeCapture();

  fs.mkdirSync(sourceDir, { recursive: true });
  fs.writeFileSync(path.join(sourceDir, 'index.ts'), 'export const version = "new";\n');
  fs.mkdirSync(targetDir, { recursive: true });
  fs.writeFileSync(path.join(targetDir, 'stale.txt'), 'old\n');
  writeJson(path.join(openclawHome, 'openclaw.json'), {});
  writeJson(configPath, {
    gateways: {
      openclaw: [{ id: 'OpenClaw' }],
    },
  });

  const code = runGatewayUpdate({
    projectRoot,
    clawkeConfigPath: configPath,
    openclawHome,
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  assert.equal(code, 0);
  assert.equal(fs.readFileSync(path.join(targetDir, 'index.ts'), 'utf-8'), 'export const version = "new";\n');
  assert.equal(fs.existsSync(path.join(targetDir, 'stale.txt')), false);
  assert.doesNotMatch(stdout.text(), /restart/i);
});

test('gateway update refreshes configured Hermes start_shell to current source', async () => {
  const { runGatewayUpdate } = await import('../dist/cli/gateway-updater.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateway-update-'));
  const projectRoot = path.join(dir, 'clawke');
  const configPath = path.join(dir, 'clawke.json');
  const hermesSourceDir = path.join(projectRoot, 'gateways', 'hermes', 'clawke');
  const stdout = makeCapture();
  const stderr = makeCapture();

  fs.mkdirSync(hermesSourceDir, { recursive: true });
  fs.writeFileSync(path.join(hermesSourceDir, 'run.py'), 'print("gateway")\n');
  writeJson(configPath, {
    gateways: {
      hermes: [{ id: 'hermes', start_shell: '/opt/hermes/bin/python /old/clawke/run.py' }],
    },
  });

  const code = runGatewayUpdate({
    projectRoot,
    clawkeConfigPath: configPath,
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
  assert.equal(code, 0);
  assert.equal(
    config.gateways.hermes[0].start_shell,
    `/opt/hermes/bin/python ${path.join(hermesSourceDir, 'run.py')}`,
  );
  assert.match(stdout.text(), /hermes gateway uses in-place source/);
});

test('cli exposes gateway update and clawke update calls it after rebuild', () => {
  const repoRoot = path.resolve(__dirname, '..', '..');
  const cliSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'cli', 'clawke.ts'), 'utf-8');
  const updateSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'cli', 'clawke-update.ts'), 'utf-8');

  assert.match(cliSource, /command === 'gateway' && subCommand === 'update'/);
  assert.match(updateSource, /runGatewayUpdate\(/);
  assert.match(updateSource, /commitCount === 0[\s\S]*return runGatewayUpdateAfterBuild\(projectRoot/);
  assert.match(updateSource, /Rebuilding server[\s\S]*const gatewayUpdateCode = runGatewayUpdateAfterBuild\(projectRoot/);
});
