import type { Request, Response } from 'express';
import type { PushDevice, PushDeviceInput, PushPlatform, PushProvider } from '../store/push-device-store.js';
import type { CloudPushClient, CloudPushDeviceRegistration, PushService } from '../services/push-service.js';
import { buildPushAlert } from '../services/push-service.js';

interface PushRouteDeps {
  deviceStore: {
    upsert: (device: PushDeviceInput) => PushDevice;
    disable?: (deviceId: string, provider: PushProvider) => boolean;
  };
  conversationStore?: {
    get: (conversationId: string) => unknown | null;
  };
  messageStore?: {
    getById: (messageId: string) => { conversationId: string; seq: number; content?: string } | null;
  };
  pushService?: Pick<PushService, 'notifyMessage'>;
  cloudClient?: Pick<CloudPushClient, 'registerDevice' | 'unregisterDevice'> | null;
}

let deps: PushRouteDeps | null = null;

export function initPushRoutes(nextDeps: PushRouteDeps): void {
  deps = nextDeps;
}

export async function registerPushDevice(req: Request, res: Response): Promise<void> {
  if (!deps) {
    res.status(503).json({ error: 'push_not_initialized' });
    return;
  }
  const validation = validateRegisterBody(req.body);
  if (validation) {
    res.status(400).json({ error: 'validation_error', message: validation });
    return;
  }

  const body = req.body as Record<string, unknown>;
  const registration = toCloudRegistration(body);
  if (deps.cloudClient) {
    const result = await deps.cloudClient.registerDevice(registration);
    if (!result.ok) {
      console.warn(
        `[Push] registerDevice failed: status=${result.status ?? 'unknown'} `
        + `error=${result.error || 'unknown'} platform=${registration.platform} `
        + `provider=${registration.pushProvider} device=${registration.deviceId} `
        + `token_len=${registration.deviceToken.length}`,
      );
      res.status(502).json({
        error: 'push_api_failed',
        message: result.error || 'registerDevice failed',
      });
      return;
    }
    console.log(`[Push] Device proxied: platform=${registration.platform} device=${registration.deviceId} token_len=${registration.deviceToken.length}`);
    res.status(201).json({ device: toResponseRegistration(registration) });
    return;
  }

  const device = deps.deviceStore.upsert({
    deviceId: firstString(body.device_id),
    userId: firstString(body.user_id) || 'local',
    platform: firstString(body.platform) as PushPlatform,
    pushProvider: firstString(body.push_provider) as PushProvider,
    deviceToken: firstString(body.device_token),
    appVersion: firstString(body.app_version) || undefined,
  });
  console.log(`[Push] Device registered: platform=${device.platform} device=${device.deviceId} token_len=${device.deviceToken.length}`);

  res.status(201).json({ device: toResponseDevice(device) });
}

export async function disablePushDevice(req: Request, res: Response): Promise<void> {
  if (!deps) {
    res.status(503).json({ error: 'push_not_initialized' });
    return;
  }
  const deviceId = firstString(req.params.deviceId);
  const provider = (firstString(req.query.push_provider) || firstString(req.body?.push_provider) || 'apns') as PushProvider;
  if (deps.cloudClient) {
    const result = await deps.cloudClient.unregisterDevice({
      deviceId,
      pushProvider: provider,
    });
    if (!result.ok) {
      console.warn(
        `[Push] unregisterDevice failed: status=${result.status ?? 'unknown'} `
        + `error=${result.error || 'unknown'} provider=${provider} device=${deviceId}`,
      );
      res.status(502).json({
        error: 'push_api_failed',
        message: result.error || 'unregisterDevice failed',
      });
      return;
    }
    res.json({ ok: true });
    return;
  }
  if (!deps.deviceStore.disable) {
    res.status(503).json({ error: 'push_not_initialized' });
    return;
  }
  const ok = deps.deviceStore.disable(deviceId, provider);
  res.json({ ok });
}

export async function sendTestPush(req: Request, res: Response): Promise<void> {
  if (!deps?.pushService) {
    res.status(503).json({ error: 'push_not_initialized' });
    return;
  }
  const body = req.body as Record<string, unknown>;
  const conversationId = firstString(body.conversation_id);
  const messageId = firstString(body.message_id);
  const gatewayId = firstString(body.gateway_id);
  const seq = Number(body.seq || 0);
  if (!conversationId || !messageId || !gatewayId || !Number.isFinite(seq)) {
    res.status(400).json({ error: 'validation_error', message: 'conversation_id, message_id, gateway_id and seq are required.' });
    return;
  }
  if (deps.conversationStore && !deps.conversationStore.get(conversationId)) {
    res.status(404).json({ error: 'conversation_not_found' });
    return;
  }
  const storedMessage = deps.messageStore?.getById(messageId);
  if (deps.messageStore && !storedMessage) {
    res.status(404).json({ error: 'message_not_found' });
    return;
  }
  if (storedMessage && storedMessage.conversationId !== conversationId) {
    res.status(400).json({ error: 'message_conversation_mismatch' });
    return;
  }
  if (storedMessage && storedMessage.seq !== seq) {
    res.status(400).json({ error: 'message_seq_mismatch' });
    return;
  }
  const badge = optionalFiniteNumber(body.badge);
  const alert = buildPushAlert(
    gatewayId,
    storedMessage?.content || firstString(body.body),
    firstString(body.title),
  );
  const result = await deps.pushService.notifyMessage({
    conversationId,
    messageId,
    gatewayId,
    seq,
    title: alert.title,
    body: alert.body,
    badge,
    userId: firstString(body.user_id) || undefined,
  });
  res.json(result);
}

function validateRegisterBody(body: unknown): string | null {
  const map = body as Record<string, unknown> | undefined;
  const platform = firstString(map?.platform);
  const provider = firstString(map?.push_provider);
  if (!firstString(map?.device_id)) return 'device_id is required.';
  if (!isPushPlatform(platform)) return 'platform must be ios, macos or android.';
  if (!isPushProvider(provider)) return 'push_provider must be apns or fcm.';
  if ((platform === 'android' && provider !== 'fcm') || (platform !== 'android' && provider !== 'apns')) {
    return 'platform and push_provider are inconsistent.';
  }
  if (!firstString(map?.device_token)) return 'device_token is required.';
  return null;
}

function toCloudRegistration(body: Record<string, unknown>): CloudPushDeviceRegistration {
  return {
    deviceId: firstString(body.device_id),
    platform: firstString(body.platform) as PushPlatform,
    pushProvider: firstString(body.push_provider) as PushProvider,
    deviceToken: firstString(body.device_token),
    appBundleId: firstString(body.app_bundle_id) || 'ai.clawke.app',
    appVersion: firstString(body.app_version) || undefined,
  };
}

function isPushPlatform(value: string): value is PushPlatform {
  return value === 'ios' || value === 'macos' || value === 'android';
}

function isPushProvider(value: string): value is PushProvider {
  return value === 'apns' || value === 'fcm';
}

function toResponseDevice(device: PushDevice): Record<string, unknown> {
  return {
    device_id: device.deviceId,
    user_id: device.userId,
    platform: device.platform,
    push_provider: device.pushProvider,
    enabled: device.enabled,
    app_version: device.appVersion,
    created_at: device.createdAt,
    updated_at: device.updatedAt,
  };
}

function toResponseRegistration(device: CloudPushDeviceRegistration): Record<string, unknown> {
  return {
    device_id: device.deviceId,
    platform: device.platform,
    push_provider: device.pushProvider,
    app_version: device.appVersion,
  };
}

function firstString(value: unknown): string {
  if (typeof value === 'string') return value.trim();
  if (Array.isArray(value) && typeof value[0] === 'string') return value[0].trim();
  return '';
}

function optionalFiniteNumber(value: unknown): number | undefined {
  if (value === undefined || value === null || value === '') return undefined;
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}
