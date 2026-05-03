import type { Request, Response } from 'express';
import type { PushDevice, PushDeviceInput, PushPlatform, PushProvider } from '../store/push-device-store.js';
import type { PushService } from '../services/push-service.js';

interface PushRouteDeps {
  deviceStore: {
    upsert: (device: PushDeviceInput) => PushDevice;
    disable?: (deviceId: string, provider: PushProvider) => boolean;
  };
  conversationStore?: {
    get: (conversationId: string) => unknown | null;
  };
  messageStore?: {
    getById: (messageId: string) => { conversationId: string; seq: number } | null;
  };
  pushService?: Pick<PushService, 'notifyMessage'>;
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
  const device = deps.deviceStore.upsert({
    deviceId: firstString(body.device_id),
    userId: firstString(body.user_id) || 'local',
    platform: firstString(body.platform) as PushPlatform,
    pushProvider: firstString(body.push_provider) as PushProvider,
    deviceToken: firstString(body.device_token),
    appVersion: firstString(body.app_version) || undefined,
  });

  res.status(201).json({ device: toResponseDevice(device) });
}

export async function disablePushDevice(req: Request, res: Response): Promise<void> {
  if (!deps?.deviceStore.disable) {
    res.status(503).json({ error: 'push_not_initialized' });
    return;
  }
  const deviceId = firstString(req.params.deviceId);
  const provider = (firstString(req.query.push_provider) || firstString(req.body?.push_provider) || 'apns') as PushProvider;
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
  const result = await deps.pushService.notifyMessage({
    conversationId,
    messageId,
    gatewayId,
    seq,
    badge,
    userId: firstString(body.user_id) || undefined,
  });
  res.json(result);
}

function validateRegisterBody(body: unknown): string | null {
  const map = body as Record<string, unknown> | undefined;
  if (!firstString(map?.device_id)) return 'device_id is required.';
  if (!isPushPlatform(firstString(map?.platform))) return 'platform must be ios or macos.';
  if (firstString(map?.push_provider) !== 'apns') return 'push_provider must be apns.';
  if (!firstString(map?.device_token)) return 'device_token is required.';
  return null;
}

function isPushPlatform(value: string): value is PushPlatform {
  return value === 'ios' || value === 'macos';
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
