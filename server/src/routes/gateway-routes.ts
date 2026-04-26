import type { Request, Response } from 'express';
import type { ConfiguredGateway, GatewayInfo } from '../types/gateways.js';
import type { GatewayStore } from '../store/gateway-store.js';
import { listConfiguredGateways as defaultListConfiguredGateways } from '../services/gateway-config-service.js';

interface GatewayRoutesDeps {
  gatewayStore: Pick<GatewayStore, 'get' | 'upsertRuntime' | 'rename' | 'deleteMissing'>;
  listConfiguredGateways?: () => ConfiguredGateway[];
  getConnectedGateways: () => GatewayInfo[];
}

let deps: GatewayRoutesDeps | null = null;

export function initGatewayRoutes(nextDeps: GatewayRoutesDeps): void {
  deps = nextDeps;
}

export async function listGateways(_req: Request, res: Response): Promise<void> {
  const activeDeps = requireDeps();
  const configured = (activeDeps.listConfiguredGateways || defaultListConfiguredGateways)();
  const connected = activeDeps.getConnectedGateways();
  const connectedMap = new Map(connected.map((item) => [item.gateway_id, item]));
  const ids = new Set<string>();
  const result: GatewayInfo[] = [];

  for (const item of configured) {
    ids.add(item.gateway_id);
    const runtime = connectedMap.get(item.gateway_id);
    const stored = activeDeps.gatewayStore.get(item.gateway_id);
    const info: GatewayInfo = runtime
      ? {
          ...runtime,
          display_name: stored?.display_name || runtime.display_name,
          capabilities: runtime.capabilities.length ? runtime.capabilities : (stored?.capabilities || item.capabilities),
        }
      : {
          gateway_id: item.gateway_id,
          display_name: stored?.display_name || item.display_name,
          gateway_type: item.gateway_type,
          status: 'disconnected',
          capabilities: stored?.capabilities?.length ? stored.capabilities : item.capabilities,
          last_connected_at: stored?.last_connected_at ?? null,
          last_seen_at: stored?.last_seen_at ?? null,
        };
    activeDeps.gatewayStore.upsertRuntime(info);
    result.push(info);
  }

  for (const item of connected) {
    if (ids.has(item.gateway_id)) continue;
    ids.add(item.gateway_id);
    const stored = activeDeps.gatewayStore.get(item.gateway_id);
    const info = { ...item, display_name: stored?.display_name || item.display_name };
    activeDeps.gatewayStore.upsertRuntime(info);
    result.push(info);
  }

  activeDeps.gatewayStore.deleteMissing([...ids]);
  res.json({ gateways: result });
}

export async function renameGateway(req: Request, res: Response): Promise<void> {
  const activeDeps = requireDeps();
  const gatewayId = String(req.params.gatewayId || '').trim();
  const displayName = String(req.body?.display_name || '').trim();
  if (!gatewayId) {
    res.status(400).json({ error: 'validation_error', message: 'gateway_id is required.' });
    return;
  }
  if (!displayName) {
    res.status(400).json({ error: 'validation_error', message: 'display_name is required.' });
    return;
  }
  const existing = activeDeps.gatewayStore.get(gatewayId);
  if (!existing) {
    res.status(404).json({ error: 'gateway_not_found', message: `Gateway not found: ${gatewayId}` });
    return;
  }
  activeDeps.gatewayStore.rename(gatewayId, displayName);
  res.json({ ok: true, gateway: { ...existing, display_name: displayName } });
}

function requireDeps(): GatewayRoutesDeps {
  if (!deps) throw new Error('gateway routes not initialized');
  return deps;
}
