const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const repoRoot = path.resolve(__dirname, '..', '..');
const installScriptPath = path.join(repoRoot, 'scripts', 'install.sh');

test('install.sh is valid bash syntax', () => {
  execFileSync('bash', ['-n', installScriptPath], { stdio: 'pipe' });
});

test('install.sh offers guided post-install actions', () => {
  const script = fs.readFileSync(installScriptPath, 'utf8');

  assert.match(script, /run_post_install_setup\(\)/);
  assert.match(script, /Install an AI gateway now\?/);
  assert.match(script, /Start Clawke Server now\?/);
  assert.match(script, /run_clawke_command\(\)/);
});

test('guided post-install commands keep stdin connected to the terminal', () => {
  const script = fs.readFileSync(installScriptPath, 'utf8');

  assert.match(script, /<\s*\/dev\/tty/);
  assert.match(script, /clawke_cmd="\$\(get_command_link_dir\)\/clawke"/);
});

test('install.sh supports local non-interactive install without post-install prompts', () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-install-test-'));
  const homeDir = path.join(tmpDir, 'home');
  const sourceDir = path.join(tmpDir, 'source');
  const installDir = path.join(tmpDir, 'install');
  const fakeBinDir = path.join(tmpDir, 'bin');

  fs.mkdirSync(path.join(sourceDir, 'server', 'dist', 'cli'), { recursive: true });
  fs.mkdirSync(path.join(sourceDir, 'server', 'config'), { recursive: true });
  fs.mkdirSync(path.join(sourceDir, 'gateways'), { recursive: true });
  fs.mkdirSync(fakeBinDir, { recursive: true });

  fs.writeFileSync(path.join(sourceDir, 'server', 'package.json'), '{"scripts":{}}\n');
  fs.writeFileSync(path.join(sourceDir, 'server', 'dist', 'cli', 'clawke.js'), 'console.log("fake clawke");\n');
  fs.writeFileSync(path.join(sourceDir, 'server', 'config', 'clawke.json'), '{"server":{"mode":"mock"}}\n');
  fs.writeFileSync(
    path.join(fakeBinDir, 'npm'),
    '#!/bin/sh\nif [ "$1" = "run" ] && [ "$2" = "build" ]; then mkdir -p dist/cli && printf "%s\\n" "console.log(\\"fake clawke\\");" > dist/cli/clawke.js; fi\nexit 0\n',
    { mode: 0o755 },
  );

  const output = execFileSync(
    'bash',
    [
      installScriptPath,
      '--local',
      sourceDir,
      '--dir',
      installDir,
      '--clawke-home',
      path.join(homeDir, '.clawke'),
      '--no-post-install',
    ],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        HOME: homeDir,
        PATH: `${fakeBinDir}:${path.join(homeDir, '.local', 'bin')}:${process.env.PATH}`,
        SHELL: '/bin/bash',
      },
    },
  );

  assert.match(output, /Installation Complete/);
  assert.doesNotMatch(output, /Continue setup now/);
  assert.ok(fs.existsSync(path.join(homeDir, '.local', 'bin', 'clawke')));
  assert.ok(fs.existsSync(path.join(homeDir, '.clawke', 'clawke.json')));
});
