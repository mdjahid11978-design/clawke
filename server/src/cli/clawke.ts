#!/usr/bin/env node
/**
 * Clawke CLI 入口
 *
 * 用法：
 *   clawke gateway install                — 自动检测并安装 Gateway 插件
 *   clawke openclaw-gateway install       — 安装 Gateway 插件到本机 OpenClaw（别名）
 *   clawke nanobot-gateway install        — 安装 Clawke channel 到本机 nanobot（别名）
 *   clawke server start                   — 启动 Clawke Server
 *   clawke --help                         — 显示帮助
 */

import fs from 'fs';
import path from 'path';
import os from 'os';
import readline from 'readline';

const args = process.argv.slice(2);
const command = args[0];
const subCommand = args[1];

// ────────────── Gateway 检测定义 ──────────────

interface GatewayInfo {
  name: string;
  displayName: string;
  configPath: string;
  installFn: () => Promise<void>;
}

/**
 * 扫描本机已安装的 Agent 平台，返回可用 gateway 列表
 * Scan locally installed agent platforms and return available gateways
 */
function detectAvailableGateways(): GatewayInfo[] {
  const gateways: GatewayInfo[] = [];

  // OpenClaw: 检查 ~/.openclaw/openclaw.json
  const openclawConfig = path.join(os.homedir(), '.openclaw', 'openclaw.json');
  gateways.push({
    name: 'openclaw',
    displayName: 'OpenClaw',
    configPath: openclawConfig,
    installFn: async () => {
      const { installOpenClawGateway } = await import('./openclaw-gateway-installer.js');
      await installOpenClawGateway();
    },
  });

  // nanobot: 检查 ~/.nanobot/config.json
  const nanobotConfig = path.join(os.homedir(), '.nanobot', 'config.json');
  gateways.push({
    name: 'nanobot',
    displayName: 'nanobot',
    configPath: nanobotConfig,
    installFn: async () => {
      const { installNanobotGateway } = await import('./nanobot-gateway-installer.js');
      await installNanobotGateway();
    },
  });

  return gateways;
}

/**
 * 交互式选择 Gateway — Interactive gateway selection
 */
async function promptGatewaySelection(gateways: GatewayInfo[]): Promise<number> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise<number>((resolve) => {
    console.log('\n  Available gateways:\n');
    gateways.forEach((gw, i) => {
      const detected = fs.existsSync(gw.configPath) ? '(detected ✓)' : '(not detected)';
      console.log(`    ${i + 1}. ${gw.displayName}  ${detected}`);
    });
    console.log('');

    rl.question('  Select gateway to install [1]: ', (answer) => {
      rl.close();
      const trimmed = answer.trim();
      if (trimmed === '') {
        resolve(0); // default: first
      } else {
        const idx = parseInt(trimmed, 10) - 1;
        if (isNaN(idx) || idx < 0 || idx >= gateways.length) {
          console.error(`[clawke] ❌ Invalid selection: ${trimmed}`);
          process.exit(1);
        }
        resolve(idx);
      }
    });
  });
}

/**
 * 统一 gateway install 入口 — Unified gateway install entry
 */
async function installGateway(): Promise<void> {
  const gateways = detectAvailableGateways();

  // 检测哪些 agent 平台已安装 — Check which agent platforms are installed
  const detected = gateways.filter(gw => fs.existsSync(gw.configPath));

  if (detected.length === 1) {
    // 只有一个平台检测到，直接安装 — Only one platform detected, install directly
    console.log(`[clawke] 🔍 Auto-detected: ${detected[0].displayName}`);
    await detected[0].installFn();

  } else if (detected.length > 1) {
    // 多个平台检测到，让用户选择 — Multiple platforms detected, let user choose
    console.log(`[clawke] 🔍 Multiple agent platforms detected.`);
    const idx = await promptGatewaySelection(detected);
    await detected[idx].installFn();

  } else {
    // 没有检测到任何平台，展示所有选项让用户选 — None detected, show all options
    console.log(`[clawke] ⚠️  No agent platform detected locally.`);
    console.log(`[clawke] Select which gateway to install (you may need to install the agent platform first):`);
    const idx = await promptGatewaySelection(gateways);
    await gateways[idx].installFn();
  }
}

async function main(): Promise<void> {
  // 统一入口：clawke gateway install
  if (command === 'gateway' && subCommand === 'install') {
    await installGateway();

  // 旧命令别名兼容 — Legacy command aliases
  } else if (command === 'openclaw-gateway' && subCommand === 'install') {
    const { installOpenClawGateway } = await import('./openclaw-gateway-installer.js');
    await installOpenClawGateway();

  } else if (command === 'nanobot-gateway' && subCommand === 'install') {
    const { installNanobotGateway } = await import('./nanobot-gateway-installer.js');
    await installNanobotGateway();

  } else if (command === 'server' && subCommand === 'start') {
    // 自动编译 TypeScript（增量模式，没改动时秒完成）— Auto-build before start
    const serverDir = path.join(__dirname, '..', '..');
    const tsconfigPath = path.join(serverDir, 'tsconfig.json');
    if (fs.existsSync(tsconfigPath)) {
      const { execSync } = await import('child_process');
      try {
        execSync('npx tsc', { cwd: serverDir, stdio: 'inherit' });
      } catch {
        console.error('[clawke] ⚠️  TypeScript build failed, starting with existing dist...');
      }
    }
    // 加载 server 入口 — Load server entry
    await import('../index.js');

  } else {
    printHelp();
    process.exit(command === '--help' || command === '-h' ? 0 : 1);
  }
}

function printHelp(): void {
  console.log(`
  Clawke CLI

  Usage:
    clawke <command>

  Commands:
    gateway install            Auto-detect and install gateway plugin
    server start               Start Clawke Server

  Legacy Commands:
    openclaw-gateway install   Install OpenClaw gateway (same as gateway install)
    nanobot-gateway install    Install nanobot gateway (same as gateway install)

  Options:
    --help, -h                 Show this help message

  Quick Start:
    clawke gateway install     # Connect to your AI agent
    clawke server start        # Start the server
`);
}

main().catch((err) => {
  console.error('[clawke] Fatal error:', err.message);
  process.exit(1);
});
