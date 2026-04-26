import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const DEFAULT_CLAWKE_HOME = path.join(os.homedir(), '.clawke');
const DEFAULT_CLAWKE_CONFIG = path.join(DEFAULT_CLAWKE_HOME, 'clawke.json');

interface RegisterGatewayOptions {
  configPath?: string;
  gatewayType: string;
  gatewayId: string;
  values?: Record<string, unknown>;
}

export function registerGatewayInClawkeConfig(options: RegisterGatewayOptions): void {
  const configPath = options.configPath || DEFAULT_CLAWKE_CONFIG;
  let config: Record<string, any> = {};

  if (fs.existsSync(configPath)) {
    try {
      config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    } catch (err: any) {
      console.error(`[clawke] ⚠️  Could not parse ${configPath}: ${err.message}`);
    }

    try {
      fs.copyFileSync(configPath, `${configPath}.bak`);
    } catch {}
  }

  if (!config.gateways || typeof config.gateways !== 'object') {
    config.gateways = {};
  }
  if (!Array.isArray(config.gateways[options.gatewayType])) {
    config.gateways[options.gatewayType] = [];
  }

  const gateways = config.gateways[options.gatewayType] as Array<Record<string, unknown>>;
  const existing = gateways.find((item) => item.id === options.gatewayId);
  const next = {
    ...(options.values || {}),
    id: options.gatewayId,
  };

  if (existing) {
    Object.assign(existing, next);
  } else {
    gateways.push(next);
  }

  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
}
