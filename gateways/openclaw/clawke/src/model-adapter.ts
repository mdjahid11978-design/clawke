import { createOpenClawGatewayRpc, type OpenClawGatewayRpc, type OpenClawGatewayRpcOptions } from "./task-adapter.ts";

export type OpenClawModelAdapterContext = {
  log?: {
    error?: (message: string) => void;
  };
};

export interface OpenClawModelAdapterOptions extends OpenClawGatewayRpcOptions {
  rpc?: OpenClawGatewayRpc;
}

export type OpenClawGatewayModel = {
  model_id: string;
  id: string;
  provider: string;
  display_name: string;
  name?: string;
  alias?: string;
  context_window?: number;
  reasoning?: boolean;
  input?: string[];
  raw_json?: Record<string, unknown>;
};

export class OpenClawModelAdapter {
  private readonly rpc: OpenClawGatewayRpc;

  constructor(options: OpenClawModelAdapterOptions = {}) {
    this.rpc = options.rpc ?? createOpenClawGatewayRpc(options);
  }

  async listModels(ctx?: OpenClawModelAdapterContext): Promise<OpenClawGatewayModel[]> {
    try {
      const payload = await this.rpc("models.list", {}, { timeoutMs: 10_000 });
      return modelCatalogPayloadToModels(payload);
    } catch (error) {
      ctx?.log?.error?.(`models.list failed: ${error instanceof Error ? error.message : String(error)}`);
      return [];
    }
  }
}

export function modelCatalogPayloadToModels(payload: unknown): OpenClawGatewayModel[] {
  if (!isRecord(payload) || !Array.isArray(payload.models)) {
    return [];
  }
  const seen = new Set<string>();
  const models: OpenClawGatewayModel[] = [];
  for (const entry of payload.models) {
    const model = modelCatalogEntryToModel(entry);
    if (!model || seen.has(model.model_id)) continue;
    seen.add(model.model_id);
    models.push(model);
  }
  return models;
}

export function modelCatalogEntryToModel(entry: unknown): OpenClawGatewayModel | undefined {
  if (!isRecord(entry)) return undefined;
  const provider = normalizeNonEmptyString(entry.provider);
  const id = normalizeNonEmptyString(entry.id) ?? normalizeNonEmptyString(entry.name);
  if (!provider || !id) return undefined;

  const modelId = modelStartsWithProvider(id, provider) ? id : `${provider}/${id}`;
  const name = normalizeNonEmptyString(entry.name);
  const alias = normalizeNonEmptyString(entry.alias);
  const model: OpenClawGatewayModel = {
    model_id: modelId,
    id,
    provider,
    display_name: alias ?? name ?? modelId,
    raw_json: entry,
  };

  if (name) model.name = name;
  if (alias) model.alias = alias;
  if (typeof entry.contextWindow === "number") model.context_window = entry.contextWindow;
  if (typeof entry.reasoning === "boolean") model.reasoning = entry.reasoning;
  if (Array.isArray(entry.input)) {
    const input = entry.input.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
    if (input.length > 0) model.input = input;
  }
  return model;
}

// 兼容旧版 string[] 模型响应路径；新代码应使用 modelCatalogPayloadToModels。
// Compatibility path for legacy string[] model responses; new code should use modelCatalogPayloadToModels.
export function modelCatalogPayloadToKeys(payload: unknown): string[] {
  if (!isRecord(payload) || !Array.isArray(payload.models)) {
    return [];
  }
  const seen = new Set<string>();
  const keys: string[] = [];
  for (const entry of payload.models) {
    const key = modelCatalogEntryToKey(entry);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    keys.push(key);
  }
  return keys;
}

// 兼容旧版 string model key 生成逻辑；新代码应使用 modelCatalogEntryToModel。
// Compatibility path for legacy string model key generation; new code should use modelCatalogEntryToModel.
export function modelCatalogEntryToKey(entry: unknown): string | undefined {
  if (!isRecord(entry)) return undefined;
  const provider = normalizeNonEmptyString(entry.provider);
  const model = normalizeNonEmptyString(entry.id) ?? normalizeNonEmptyString(entry.name);
  if (!provider || !model) return undefined;
  return modelStartsWithProvider(model, provider) ? model : `${provider}/${model}`;
}

function modelStartsWithProvider(model: string, provider: string): boolean {
  return model.toLowerCase().startsWith(`${provider.toLowerCase()}/`);
}

function normalizeNonEmptyString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object");
}
