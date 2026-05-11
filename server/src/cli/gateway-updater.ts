import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const DEFAULT_PROJECT_ROOT = path.resolve(__dirname, '..', '..', '..');
const DEFAULT_CLAWKE_HOME = process.env.CLAWKE_DATA_DIR || path.join(os.homedir(), '.clawke');
const DEFAULT_CLAWKE_CONFIG = path.join(DEFAULT_CLAWKE_HOME, 'clawke.json');
const DEFAULT_OPENCLAW_HOME = path.join(os.homedir(), '.openclaw');

interface WritableLike {
  write(chunk: string): unknown;
}

interface GatewayUpdateOptions {
  projectRoot?: string;
  clawkeConfigPath?: string;
  openclawHome?: string;
  localOnly?: boolean;
  stdout?: WritableLike;
  stderr?: WritableLike;
}

interface GatewayEntry {
  id?: unknown;
  start_shell?: unknown;
  [key: string]: unknown;
}

interface ConfiguredGateway {
  type: string;
  entry: GatewayEntry;
}

interface ClawkeConfig {
  gateways?: Record<string, unknown>;
  [key: string]: unknown;
}

function readConfig(configPath: string, stderr: WritableLike): ClawkeConfig | null {
  if (!fs.existsSync(configPath)) return null;
  try {
    return JSON.parse(fs.readFileSync(configPath, 'utf-8')) as ClawkeConfig;
  } catch (err: any) {
    stderr.write(`[clawke] ❌ Could not parse ${configPath}: ${err.message}\n`);
    return null;
  }
}

function writeConfig(configPath: string, config: ClawkeConfig): void {
  try {
    fs.copyFileSync(configPath, `${configPath}.bak`);
  } catch {}
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
}

function collectConfiguredGateways(config: ClawkeConfig | null): ConfiguredGateway[] {
  const gateways = config?.gateways;
  if (!gateways || typeof gateways !== 'object') return [];

  const result: ConfiguredGateway[] = [];
  for (const [type, value] of Object.entries(gateways)) {
    if (!Array.isArray(value)) continue;
    for (const entry of value) {
      if (entry && typeof entry === 'object' && !Array.isArray(entry)) {
        result.push({ type, entry: entry as GatewayEntry });
      }
    }
  }
  return result;
}

function replaceRunScript(startShell: string, runScript: string): string | null {
  const match = startShell.match(/^(.*\s)\/[^\s"'`]*run\.py\s*$/);
  if (!match) return null;
  return `${match[1]}${runScript}`;
}

function updateHermesGateway(
  projectRoot: string,
  entry: GatewayEntry,
  stdout: WritableLike,
  stderr: WritableLike,
): boolean {
  const runScript = path.join(projectRoot, 'gateways', 'hermes', 'clawke', 'run.py');
  if (!fs.existsSync(runScript)) {
    stderr.write(`[clawke] ❌ Hermes gateway source not found: ${runScript}\n`);
    return false;
  }

  if (typeof entry.start_shell === 'string') {
    const nextStartShell = replaceRunScript(entry.start_shell, runScript);
    if (nextStartShell) {
      entry.start_shell = nextStartShell;
    }
  }

  stdout.write('[clawke] ✓ hermes gateway uses in-place source; start command refreshed\n');
  return true;
}

function updateOpenClawGateway(
  projectRoot: string,
  openclawHome: string,
  localOnly: boolean,
  stdout: WritableLike,
  stderr: WritableLike,
): boolean {
  const sourceDir = path.join(projectRoot, 'gateways', 'openclaw', 'clawke');
  const openclawConfig = path.join(openclawHome, 'openclaw.json');
  const targetDir = path.join(openclawHome, 'extensions', 'clawke');

  if (!fs.existsSync(sourceDir)) {
    stderr.write(`[clawke] ❌ OpenClaw gateway source not found: ${sourceDir}\n`);
    return false;
  }

  if (!fs.existsSync(openclawConfig)) {
    if (localOnly) {
      stdout.write('[clawke] ⚠️ Skipping OpenClaw gateway sync: local OpenClaw install was not found.\n');
      return true;
    }
    stderr.write('[clawke] ⚠️ OpenClaw is configured, but local OpenClaw install was not found.\n');
    stderr.write('[clawke] Remote gateway cannot be updated automatically.\n');
    stderr.write(`  scp -r ${sourceDir}/ user@<REMOTE>:~/.openclaw/extensions/clawke/\n`);
    return false;
  }

  fs.rmSync(targetDir, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(targetDir), { recursive: true });
  fs.cpSync(sourceDir, targetDir, { recursive: true });
  stdout.write(`[clawke] ✓ OpenClaw gateway synced to ${targetDir}\n`);

  if (fs.existsSync(path.join(targetDir, 'package.json'))) {
    stdout.write('[clawke] Installing OpenClaw gateway dependencies...\n');
    const result = spawnSync('npm', ['install', '--production'], {
      cwd: targetDir,
      stdio: 'inherit',
      shell: process.platform === 'win32',
    });
    if (result.status !== 0) {
      stderr.write(`[clawke] ❌ Failed to install OpenClaw gateway dependencies in ${targetDir}\n`);
      return false;
    }
  }

  return true;
}

export function runGatewayUpdate(options: GatewayUpdateOptions = {}): number {
  const projectRoot = options.projectRoot || DEFAULT_PROJECT_ROOT;
  const configPath = options.clawkeConfigPath || DEFAULT_CLAWKE_CONFIG;
  const openclawHome = options.openclawHome || DEFAULT_OPENCLAW_HOME;
  const localOnly = options.localOnly === true;
  const stdout = options.stdout || process.stdout;
  const stderr = options.stderr || process.stderr;
  const config = readConfig(configPath, stderr);
  const gateways = collectConfiguredGateways(config);

  if (!config || gateways.length === 0) {
    stdout.write('[clawke] No configured gateways found. Run `clawke gateway install` first.\n');
    return 0;
  }

  stdout.write('[clawke] Updating configured gateways...\n');

  let failed = 0;
  let changedConfig = false;
  for (const gateway of gateways) {
    const before = JSON.stringify(gateway.entry);
    let ok = true;

    if (gateway.type === 'hermes') {
      ok = updateHermesGateway(projectRoot, gateway.entry, stdout, stderr);
    } else if (gateway.type === 'openclaw') {
      ok = updateOpenClawGateway(projectRoot, openclawHome, localOnly, stdout, stderr);
    } else {
      stdout.write(`[clawke] ⚠️ Skipping unknown gateway type: ${gateway.type}\n`);
    }

    if (!ok) failed += 1;
    if (JSON.stringify(gateway.entry) !== before) changedConfig = true;
  }

  if (changedConfig) {
    writeConfig(configPath, config);
    stdout.write(`[clawke] ✓ Gateway config updated: ${configPath}\n`);
  }

  if (failed > 0) {
    stderr.write(`[clawke] ❌ Gateway update failed for ${failed} configured gateway(s).\n`);
    return 1;
  }

  stdout.write('[clawke] ✓ Gateway update complete\n');
  return 0;
}
