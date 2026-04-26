/**
 * Nanobot Gateway 自动安装器
 *
 * 检测本机 nanobot → 拷贝 channel 文件 → 合并配置 → 提示重启
 */
import fs from 'fs';
import path from 'path';
import os from 'os';
import { registerGatewayInClawkeConfig } from './clawke-config-writer.js';

const NANOBOT_HOME = path.join(os.homedir(), '.nanobot');
const NANOBOT_CONFIG = path.join(NANOBOT_HOME, 'config.json');

/** 获取项目内 nanobot channel 源路径 */
function getSourceDir(): string {
  // dist/cli/nanobot-gateway-installer.js → server/ → ../gateways/nanobot/clawke/
  return path.join(__dirname, '..', '..', '..', 'gateways', 'nanobot', 'clawke');
}

export async function installNanobotGateway(): Promise<void> {
  console.log('[clawke] 🔍 Detecting nanobot installation...');

  // Step 1: 检测 nanobot
  if (!fs.existsSync(NANOBOT_CONFIG)) {
    printRemoteGuide();
    return;
  }

  console.log(`[clawke] ✅ nanobot detected: ${NANOBOT_CONFIG}`);

  const sourceDir = getSourceDir();
  if (!fs.existsSync(sourceDir)) {
    console.error(`[clawke] ❌ Nanobot channel source not found: ${sourceDir}`);
    console.error('[clawke] Please run this command from the Clawke project root.');
    process.exit(1);
  }

  // Step 2: 拷贝 channel 文件到 nanobot channels 目录
  const nanobotChannelsDir = findNanobotChannelsDir();
  if (nanobotChannelsDir) {
    const targetFile = path.join(nanobotChannelsDir, 'clawke.py');
    const sourceFile = path.join(sourceDir, 'clawke.py');
    if (fs.existsSync(sourceFile)) {
      fs.copyFileSync(sourceFile, targetFile);
      console.log(`[clawke] ✅ Channel copied: ${sourceFile} → ${targetFile}`);
    }
  } else {
    console.log('[clawke] ⚠️  Could not locate nanobot channels directory.');
    console.log('  Please manually copy gateways/nanobot/clawke/clawke.py to your nanobot channels/ dir.');
  }

  // Step 3: 合并 nanobot 配置
  mergeNanobotConfig();
  mergeClawkeConfig();

  console.log(`
[clawke] ✅ Installation complete!

  Please restart nanobot to activate the Clawke channel:
    cd <nanobot-project> && python3 -m nanobot
`);
}

/** 尝试定位 nanobot 源码中的 channels 目录 */
function findNanobotChannelsDir(): string | null {
  // 常见位置
  const candidates = [
    // 用户可能在同级目录
    path.join(__dirname, '..', '..', '..', '..', 'nanobot', 'nanobot', 'channels'),
    // 或通过环境变量
    process.env.NANOBOT_SRC
      ? path.join(process.env.NANOBOT_SRC, 'nanobot', 'channels')
      : '',
  ].filter(Boolean);

  for (const dir of candidates) {
    if (dir && fs.existsSync(dir)) {
      return dir;
    }
  }
  return null;
}

function mergeNanobotConfig(): void {
  let config: Record<string, any> = {};
  try {
    config = JSON.parse(fs.readFileSync(NANOBOT_CONFIG, 'utf-8'));
  } catch (err: any) {
    console.error(`[clawke] ⚠️  Could not parse ${NANOBOT_CONFIG}: ${err.message}`);
    return;
  }

  // 备份
  try {
    fs.copyFileSync(NANOBOT_CONFIG, NANOBOT_CONFIG + '.bak');
    console.log(`[clawke] 📋 Config backed up: ${NANOBOT_CONFIG}.bak`);
  } catch {}

  // 合并 channels.clawke
  if (!config.channels) config.channels = {};
  if (!config.channels.clawke) {
    config.channels.clawke = {
      enabled: true,
      url: 'ws://127.0.0.1:8766',
      accountId: 'nanobot',
      allowFrom: ['*'],
    };
    console.log('[clawke] ✅ Added channels.clawke config');
  } else {
    config.channels.clawke.enabled = true;
    console.log('[clawke] ✅ Enabled channels.clawke (existing config preserved)');
  }

  fs.writeFileSync(NANOBOT_CONFIG, JSON.stringify(config, null, 2) + '\n');
  console.log(`[clawke] ✅ Config updated: ${NANOBOT_CONFIG}`);
}

function mergeClawkeConfig(): void {
  registerGatewayInClawkeConfig({
    gatewayType: 'nanobot',
    gatewayId: 'nanobot',
  });
  console.log('[clawke] ✅ Registered nanobot gateway in ~/.clawke/clawke.json');
}

function printRemoteGuide(): void {
  console.log(`[clawke] nanobot not detected on this machine.

If nanobot is installed elsewhere, configure it manually:

  1. Add to ~/.nanobot/config.json:
     {
       "channels": {
         "clawke": {
           "enabled": true,
           "url": "ws://<CLAWKE_SERVER_IP>:8766",
           "accountId": "nanobot",
           "allowFrom": ["*"]
         }
       }
     }

  2. Copy the channel file:
     cp gateways/nanobot/clawke/clawke.py <nanobot-path>/nanobot/channels/

  3. Restart nanobot`);
}
