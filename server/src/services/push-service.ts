import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as http2 from 'node:http2';
import type { PushDevice } from '../store/push-device-store.js';

export interface PushMessage {
  conversationId: string;
  messageId: string;
  gatewayId: string;
  seq: number;
  title?: string;
  body?: string;
  badge?: number;
  userId?: string;
}

export interface PushResult {
  attempted: number;
  sent: number;
  failed: number;
  details: PushDeliveryDetail[];
}

export interface PushDeliveryDetail {
  deviceId: string;
  platform: PushDevice['platform'];
  ok: boolean;
  status?: number;
  error?: string;
}

export interface ApnsPayload {
  aps: {
    alert: {
      title: string;
      body: string;
    };
    badge?: number;
    sound?: string;
    'content-available'?: 1;
  };
  conversation_id: string;
  message_id: string;
  gateway_id: string;
  seq: number;
}

export interface ApnsProvider {
  send(device: PushDevice, payload: ApnsPayload): Promise<{ ok: boolean; status?: number; error?: string }>;
}

interface PushServiceDeps {
  listDevices: (userId?: string) => PushDevice[];
  apnsProvider?: ApnsProvider | null;
}

export class PushService {
  constructor(private deps: PushServiceDeps) {}

  async notifyMessage(message: PushMessage): Promise<PushResult> {
    const devices = this.deps
      .listDevices(message.userId)
      .filter((device) => device.enabled && device.pushProvider === 'apns');
    const provider = this.deps.apnsProvider;
    if (!provider) {
      if (devices.length > 0) {
        console.warn(`[Push] APNs provider not configured; skipped ${devices.length} devices`);
      }
      return {
        attempted: devices.length,
        sent: 0,
        failed: devices.length,
        details: devices.map((device) => ({
          deviceId: device.deviceId,
          platform: device.platform,
          ok: false,
          error: 'apns_provider_not_configured',
        })),
      };
    }

    let sent = 0;
    let failed = 0;
    const details: PushDeliveryDetail[] = [];
    for (const device of devices) {
      const payload = buildApnsPayload(message, {
        playSound: device.platform !== 'macos',
      });
      try {
        const result = await provider.send(device, payload);
        details.push({
          deviceId: device.deviceId,
          platform: device.platform,
          ok: result.ok,
          status: result.status,
          error: result.error,
        });
        console.log(`[Push] APNs result device=${device.deviceId} platform=${device.platform} ok=${result.ok} status=${result.status ?? 'unknown'}${result.error ? ` error=${result.error}` : ''}`);
        if (result.ok) sent++;
        else failed++;
      } catch (error) {
        failed++;
        const message = error instanceof Error ? error.message : String(error);
        details.push({
          deviceId: device.deviceId,
          platform: device.platform,
          ok: false,
          error: message,
        });
        console.warn(`[Push] APNs send failed: ${message}`);
      }
    }
    return { attempted: devices.length, sent, failed, details };
  }
}

export function buildApnsPayload(
  message: PushMessage,
  options: { playSound?: boolean } = {},
): ApnsPayload {
  const alert = buildPushAlert(message.gatewayId, message.body, message.title);
  const payload: ApnsPayload = {
    aps: {
      alert: {
        title: alert.title,
        body: alert.body,
      },
    },
    conversation_id: message.conversationId,
    message_id: message.messageId,
    gateway_id: message.gatewayId,
    seq: message.seq,
  };
  if (typeof message.badge === 'number' && Number.isFinite(message.badge)) {
    payload.aps.badge = Math.max(0, Math.floor(message.badge));
  }
  if (options.playSound !== false) {
    payload.aps.sound = 'default';
  }
  return payload;
}

export function buildPushAlert(gatewayId: string, body?: string, title?: string): { title: string; body: string } {
  return {
    title: sanitizePushText(title || gatewayId) || 'Clawke',
    body: truncatePushPreview(sanitizePushText(body) || 'Open Clawke to sync.'),
  };
}

function sanitizePushText(value?: string): string {
  return (value || '').replace(/\s+/g, ' ').trim();
}

function truncatePushPreview(value: string): string {
  return value.length > 100 ? `${value.slice(0, 100)}...` : value;
}

export interface ApnsHttp2Config {
  keyId: string;
  teamId: string;
  bundleId: string;
  privateKey: string;
  sandbox: boolean;
}

export class ApnsHttp2Provider implements ApnsProvider {
  constructor(private config: ApnsHttp2Config) {}

  async send(device: PushDevice, payload: ApnsPayload): Promise<{ ok: boolean; status?: number; error?: string }> {
    const origin = this.config.sandbox
      ? 'https://api.sandbox.push.apple.com'
      : 'https://api.push.apple.com';
    const jwt = createApnsJwt(this.config);

    return new Promise((resolve) => {
      const client = http2.connect(origin);
      let status = 0;
      let raw = '';

      client.once('error', (error) => {
        client.close();
        resolve({ ok: false, error: error.message });
      });

      const req = client.request({
        ':method': 'POST',
        ':path': `/3/device/${device.deviceToken}`,
        authorization: `bearer ${jwt}`,
        'apns-topic': this.config.bundleId,
        'apns-push-type': 'alert',
        'apns-priority': '10',
      });

      req.setEncoding('utf8');
      req.on('response', (headers) => {
        status = Number(headers[':status'] || 0);
      });
      req.on('data', (chunk) => {
        raw += chunk;
      });
      req.on('error', (error) => {
        client.close();
        resolve({ ok: false, status, error: error.message });
      });
      req.on('end', () => {
        client.close();
        resolve({
          ok: status >= 200 && status < 300,
          status,
          error: status >= 200 && status < 300 ? undefined : raw,
        });
      });
      req.end(JSON.stringify(payload));
    });
  }
}

export function createApnsProviderFromEnv(env: NodeJS.ProcessEnv = process.env): ApnsProvider | null {
  const keyId = env.APNS_KEY_ID || '';
  const teamId = env.APNS_TEAM_ID || '';
  const bundleId = env.APNS_BUNDLE_ID || '';
  const privateKey = env.APNS_PRIVATE_KEY
    || (env.APNS_PRIVATE_KEY_PATH ? readOptionalFile(env.APNS_PRIVATE_KEY_PATH) : '');
  const missing = [
    keyId ? '' : 'APNS_KEY_ID',
    teamId ? '' : 'APNS_TEAM_ID',
    bundleId ? '' : 'APNS_BUNDLE_ID',
    privateKey ? '' : 'APNS_PRIVATE_KEY/APNS_PRIVATE_KEY_PATH',
  ].filter(Boolean);
  if (missing.length > 0) {
    console.warn(`[Push] APNs provider disabled: missing ${missing.join(', ')}`);
    return null;
  }
  const sandbox = (env.APNS_ENV || '').toLowerCase() !== 'production'
    && env.APNS_USE_SANDBOX !== '0';
  const keySource = env.APNS_PRIVATE_KEY ? 'inline' : 'file';
  console.log(`[Push] APNs provider configured: key_id=${maskApnsValue(keyId)} team_id=${maskApnsValue(teamId)} bundle_id=${bundleId} env=${sandbox ? 'development' : 'production'} private_key=${keySource}`);
  return new ApnsHttp2Provider({ keyId, teamId, bundleId, privateKey, sandbox });
}

function maskApnsValue(value: string): string {
  if (value.length <= 4) return '****';
  return `${value.slice(0, 4)}...`;
}

function createApnsJwt(config: ApnsHttp2Config): string {
  const header = base64UrlJson({ alg: 'ES256', kid: config.keyId });
  const claims = base64UrlJson({
    iss: config.teamId,
    iat: Math.floor(Date.now() / 1000),
  });
  const body = `${header}.${claims}`;
  const sign = crypto.createSign('SHA256');
  sign.update(body);
  sign.end();
  const signature = sign.sign({
    key: config.privateKey,
    dsaEncoding: 'ieee-p1363',
  });
  return `${body}.${base64Url(signature)}`;
}

function base64UrlJson(value: Record<string, unknown>): string {
  return base64Url(Buffer.from(JSON.stringify(value)));
}

function base64Url(value: Buffer): string {
  return value.toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function readOptionalFile(path: string): string {
  try {
    return fs.readFileSync(path, 'utf8');
  } catch {
    return '';
  }
}
