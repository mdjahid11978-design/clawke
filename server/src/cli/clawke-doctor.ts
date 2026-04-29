import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { resolveGatewayStartShell } from './gateway-start-config.js';

type DoctorStatus = 'ok' | 'warn' | 'error' | 'info';

interface DoctorCheck {
  section: string;
  status: DoctorStatus;
  message: string;
  detail?: string;
}

interface GatewayInstance {
  id?: unknown;
  start_shell?: unknown;
}

interface DoctorOptions {
  clawkeHome?: string;
  homeDir?: string;
  projectRoot?: string;
  serverDir?: string;
  stdout?: NodeJS.WritableStream;
  env?: NodeJS.ProcessEnv;
}

export interface DoctorResult {
  ok: boolean;
  warningCount: number;
  errorCount: number;
  checks: DoctorCheck[];
}

const DEFAULT_SERVER_DIR = path.resolve(__dirname, '..', '..');
const DEFAULT_PROJECT_ROOT = path.resolve(DEFAULT_SERVER_DIR, '..');

function resolveClawkeHome(options: DoctorOptions): string {
  if (options.clawkeHome) return options.clawkeHome;
  const env = options.env || process.env;
  return env.CLAWKE_DATA_DIR || path.join(options.homeDir || os.homedir(), '.clawke');
}

function addCheck(
  checks: DoctorCheck[],
  section: string,
  status: DoctorStatus,
  message: string,
  detail?: string,
): void {
  checks.push({ section, status, message, detail });
}

function readJson(filePath: string): { value?: any; error?: string } {
  try {
    return { value: JSON.parse(fs.readFileSync(filePath, 'utf-8')) };
  } catch (err: any) {
    return { error: err?.message || String(err) };
  }
}

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: any) {
    return err?.code === 'EPERM';
  }
}

function readPidFile(pidPath: string): number | null {
  try {
    const pid = Number.parseInt(fs.readFileSync(pidPath, 'utf-8').trim(), 10);
    return Number.isFinite(pid) ? pid : null;
  } catch {
    return null;
  }
}

function collectGatewayInstances(config: any): GatewayInstance[] {
  if (!config || typeof config !== 'object' || !config.gateways || typeof config.gateways !== 'object') {
    return [];
  }

  const instances: GatewayInstance[] = [];
  for (const value of Object.values(config.gateways)) {
    if (Array.isArray(value)) instances.push(...value);
  }
  return instances;
}

function validatePort(checks: DoctorCheck[], config: any, key: string): void {
  const value = config?.server?.[key];
  if (value === undefined) return;
  const valid = Number.isInteger(value) && value > 0 && value <= 65535;
  addCheck(
    checks,
    'Configuration',
    valid ? 'ok' : 'error',
    `${key}: ${value}`,
    valid ? undefined : 'Expected an integer between 1 and 65535.',
  );
}

function inspectProjectFiles(checks: DoctorCheck[], projectRoot: string, serverDir: string): void {
  const files = [
    [path.join(serverDir, 'package.json'), 'server/package.json'],
    [path.join(serverDir, 'tsconfig.json'), 'server/tsconfig.json'],
    [path.join(serverDir, 'dist', 'index.js'), 'server/dist/index.js'],
    [path.join(serverDir, 'dist', 'cli', 'clawke.js'), 'server/dist/cli/clawke.js'],
  ] as const;

  for (const [filePath, label] of files) {
    addCheck(
      checks,
      'Project',
      fs.existsSync(filePath) ? 'ok' : 'warn',
      label,
      fs.existsSync(filePath) ? undefined : 'Missing; run `cd server && npm run build`.',
    );
  }

  const clientPubspec = path.join(projectRoot, 'client', 'pubspec.yaml');
  addCheck(
    checks,
    'Project',
    fs.existsSync(clientPubspec) ? 'ok' : 'info',
    'client/pubspec.yaml',
    fs.existsSync(clientPubspec) ? undefined : 'Flutter client not found in this checkout.',
  );
}

function inspectAgentPlatforms(checks: DoctorCheck[], homeDir: string): void {
  const platforms = [
    ['OpenClaw', path.join(homeDir, '.openclaw', 'openclaw.json')],
    ['Hermes', path.join(homeDir, '.hermes')],
    ['nanobot', path.join(homeDir, '.nanobot', 'config.json')],
  ] as const;

  for (const [name, configPath] of platforms) {
    const detected = fs.existsSync(configPath);
    addCheck(
      checks,
      'Agent Platforms',
      detected ? 'ok' : 'info',
      `${name}: ${detected ? 'detected' : 'not detected'}`,
      configPath,
    );
  }
}

function inspectServerPid(checks: DoctorCheck[], clawkeHome: string): void {
  const pidPath = path.join(clawkeHome, 'server.pid');
  const pid = readPidFile(pidPath);
  if (!fs.existsSync(pidPath)) {
    addCheck(checks, 'Runtime', 'info', 'Clawke Server is not running', 'No server.pid file.');
    return;
  }
  if (!pid) {
    addCheck(checks, 'Runtime', 'warn', 'server.pid is invalid', pidPath);
    return;
  }

  addCheck(
    checks,
    'Runtime',
    isProcessAlive(pid) ? 'ok' : 'warn',
    isProcessAlive(pid) ? `Clawke Server is running (PID ${pid})` : `Clawke Server PID is stale (${pid})`,
    pidPath,
  );
}

function inspectGatewayPids(checks: DoctorCheck[], clawkeHome: string, gateways: GatewayInstance[]): void {
  for (const gateway of gateways) {
    const id = typeof gateway.id === 'string' ? gateway.id : '';
    if (!id) {
      addCheck(checks, 'Gateways', 'error', 'Gateway entry is missing id');
      continue;
    }

    const startShell = resolveGatewayStartShell(gateway);
    addCheck(
      checks,
      'Gateways',
      startShell ? 'ok' : 'info',
      startShell ? `${id} has local start command` : `${id} has no local start command`,
      startShell || 'External gateway should connect to Clawke Server by itself.',
    );

    const pidPath = path.join(clawkeHome, `${id}-gateway.pid`);
    if (!fs.existsSync(pidPath)) {
      addCheck(checks, 'Gateways', 'info', `${id} gateway is not running`, 'No gateway PID file.');
      continue;
    }

    const pid = readPidFile(pidPath);
    if (!pid) {
      addCheck(checks, 'Gateways', 'warn', `${id} gateway PID file is invalid`, pidPath);
      continue;
    }

    addCheck(
      checks,
      'Gateways',
      isProcessAlive(pid) ? 'ok' : 'warn',
      isProcessAlive(pid) ? `${id} gateway is running (PID ${pid})` : `${id} gateway PID is stale (${pid})`,
      pidPath,
    );
  }
}

function statusIcon(status: DoctorStatus): string {
  switch (status) {
    case 'ok': return '✅';
    case 'warn': return '⚠️';
    case 'error': return '❌';
    case 'info': return 'ℹ️';
  }
}

function renderChecks(checks: DoctorCheck[], stdout: NodeJS.WritableStream): void {
  stdout.write('\nClawke Doctor\n\n');

  let currentSection = '';
  for (const check of checks) {
    if (check.section !== currentSection) {
      currentSection = check.section;
      stdout.write(`◆ ${currentSection}\n`);
    }
    stdout.write(`  ${statusIcon(check.status)} ${check.message}`);
    if (check.detail) stdout.write(` (${check.detail})`);
    stdout.write('\n');
  }
}

export function runClawkeDoctor(options: DoctorOptions = {}): DoctorResult {
  const stdout = options.stdout || process.stdout;
  const clawkeHome = resolveClawkeHome(options);
  const homeDir = options.homeDir || os.homedir();
  const projectRoot = options.projectRoot || DEFAULT_PROJECT_ROOT;
  const serverDir = options.serverDir || DEFAULT_SERVER_DIR;
  const checks: DoctorCheck[] = [];

  inspectProjectFiles(checks, projectRoot, serverDir);
  inspectAgentPlatforms(checks, homeDir);
  inspectServerPid(checks, clawkeHome);

  const configPath = path.join(clawkeHome, 'clawke.json');
  let config: any = null;
  if (!fs.existsSync(configPath)) {
    addCheck(
      checks,
      'Configuration',
      'warn',
      'clawke.json is missing',
      `${configPath}; run \`clawke gateway install\` or \`clawke server start\`.`,
    );
  } else {
    const parsed = readJson(configPath);
    if (parsed.error) {
      addCheck(checks, 'Configuration', 'error', 'clawke.json is not valid JSON', parsed.error);
    } else {
      config = parsed.value;
      addCheck(checks, 'Configuration', 'ok', 'clawke.json parsed', configPath);
      validatePort(checks, config, 'clientPort');
      validatePort(checks, config, 'httpPort');
      validatePort(checks, config, 'upstreamPort');
      validatePort(checks, config, 'mediaPort');
    }
  }

  const gateways = collectGatewayInstances(config);
  if (config) {
    const suffix = gateways.length === 1 ? '' : 's';
    addCheck(checks, 'Gateways', gateways.length > 0 ? 'ok' : 'warn', `${gateways.length} gateway instance${suffix} configured`);
  }
  inspectGatewayPids(checks, clawkeHome, gateways);

  renderChecks(checks, stdout);

  const warningCount = checks.filter((check) => check.status === 'warn').length;
  const errorCount = checks.filter((check) => check.status === 'error').length;
  stdout.write(`\nSummary: ${errorCount} error(s), ${warningCount} warning(s).\n`);

  return {
    ok: errorCount === 0,
    warningCount,
    errorCount,
    checks,
  };
}
