import type BetterSqlite3 from 'better-sqlite3';
import type { Database } from './database.js';

export type GatewayModelCacheInput = string | Record<string, unknown>;

export type CachedGatewayModel = {
  model_id: string;
  id: string;
  provider?: string;
  display_name: string;
  name?: string;
  alias?: string;
  context_window?: number;
  reasoning?: boolean;
  input?: string[];
};

type GatewayModelCacheRow = {
  model_id: string;
  display_name: string | null;
  provider: string | null;
  raw_json: string | null;
};

export class GatewayModelCacheStore {
  private readonly selectStmt: BetterSqlite3.Statement;
  private readonly replaceTransaction: BetterSqlite3.Transaction;

  constructor(database: Database) {
    const db = database.raw;
    db.exec(`
      CREATE TABLE IF NOT EXISTS gateway_model_cache (
        gateway_id TEXT NOT NULL,
        model_id TEXT NOT NULL,
        display_name TEXT,
        provider TEXT,
        raw_json TEXT,
        updated_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        PRIMARY KEY (gateway_id, model_id)
      );
      CREATE INDEX IF NOT EXISTS idx_gateway_model_cache_gateway
        ON gateway_model_cache(gateway_id, model_id);
    `);

    this.selectStmt = db.prepare(`
      SELECT model_id, display_name, provider, raw_json
      FROM gateway_model_cache
      WHERE gateway_id = ?
      ORDER BY model_id ASC
    `);
    const deleteStmt = db.prepare('DELETE FROM gateway_model_cache WHERE gateway_id = ?');
    const insertStmt = db.prepare(`
      INSERT INTO gateway_model_cache (
        gateway_id,
        model_id,
        display_name,
        provider,
        raw_json,
        updated_at,
        last_seen_at
      ) VALUES (
        @gateway_id,
        @model_id,
        @display_name,
        @provider,
        @raw_json,
        @updated_at,
        @last_seen_at
      )
    `);
    this.replaceTransaction = db.transaction((gatewayId: string, models: CachedGatewayModel[], now: number) => {
      deleteStmt.run(gatewayId);
      for (const model of models) {
        insertStmt.run({
          gateway_id: gatewayId,
          model_id: model.model_id,
          display_name: model.display_name,
          provider: model.provider ?? null,
          raw_json: JSON.stringify(model),
          updated_at: now,
          last_seen_at: now,
        });
      }
    });
  }

  getGatewayModels(gatewayId: string): CachedGatewayModel[] {
    return (this.selectStmt.all(gatewayId) as GatewayModelCacheRow[])
      .map(rowToGatewayModel)
      .filter((model): model is CachedGatewayModel => Boolean(model));
  }

  replaceGatewayModels(gatewayId: string, models: GatewayModelCacheInput[]): void {
    const uniqueModels = new Map<string, CachedGatewayModel>();
    for (const input of models) {
      const model = normalizeGatewayModel(input);
      if (model) uniqueModels.set(model.model_id, model);
    }
    const sortedModels = [...uniqueModels.values()].sort((a, b) => a.model_id.localeCompare(b.model_id));
    this.replaceTransaction(gatewayId, sortedModels, Date.now());
  }
}

export function normalizeGatewayModel(input: GatewayModelCacheInput): CachedGatewayModel | null {
  if (typeof input === 'string') {
    return modelFromId(input);
  }

  const modelId =
    normalizeString(input.model_id) ??
    normalizeString(input.modelId) ??
    modelIdFromProviderAndId(normalizeString(input.provider), normalizeString(input.id));
  if (!modelId) return null;

  const provider = normalizeString(input.provider) ?? providerFromModelId(modelId) ?? undefined;
  const id = normalizeString(input.id) ?? idFromModelId(modelId, provider);
  const displayName =
    normalizeString(input.display_name) ??
    normalizeString(input.displayName) ??
    normalizeString(input.alias) ??
    normalizeString(input.name) ??
    modelId;
  const model: CachedGatewayModel = {
    model_id: modelId,
    id,
    display_name: displayName,
  };

  if (provider) model.provider = provider;
  copyString(input.name, (value) => { model.name = value; });
  copyString(input.alias, (value) => { model.alias = value; });
  const contextWindow = numberValue(input.context_window) ?? numberValue(input.contextWindow);
  if (contextWindow !== undefined) model.context_window = contextWindow;
  if (typeof input.reasoning === 'boolean') model.reasoning = input.reasoning;
  if (Array.isArray(input.input)) {
    const inputTypes = input.input.filter((item): item is string => typeof item === 'string' && item.trim().length > 0);
    if (inputTypes.length > 0) model.input = inputTypes;
  }
  return model;
}

function rowToGatewayModel(row: GatewayModelCacheRow): CachedGatewayModel | null {
  const raw = parseRawJson(row.raw_json);
  return normalizeGatewayModel({
    ...raw,
    // 兼容旧版只保存 model_id 的缓存记录；新写入路径会保存完整 raw_json。
    // Compatibility for legacy cache rows that only stored model_id; new writes preserve raw_json.
    model_id: row.model_id,
    display_name: row.display_name ?? raw.display_name,
    provider: row.provider ?? raw.provider,
  });
}

function modelFromId(modelIdValue: string): CachedGatewayModel | null {
  const modelId = modelIdValue.trim();
  if (!modelId) return null;
  const provider = providerFromModelId(modelId) ?? undefined;
  return {
    model_id: modelId,
    id: idFromModelId(modelId, provider),
    provider,
    display_name: modelId,
  };
}

function modelIdFromProviderAndId(provider?: string, id?: string): string | null {
  if (!provider || !id) return null;
  return id.toLowerCase().startsWith(`${provider.toLowerCase()}/`) ? id : `${provider}/${id}`;
}

function idFromModelId(modelId: string, provider?: string): string {
  if (!provider) return modelId;
  const prefix = `${provider}/`;
  return modelId.toLowerCase().startsWith(prefix.toLowerCase())
    ? modelId.slice(prefix.length) || modelId
    : modelId;
}

function providerFromModelId(modelId: string): string | null {
  const index = modelId.indexOf('/');
  if (index <= 0) return null;
  return modelId.slice(0, index);
}

function parseRawJson(rawJson: string | null): Record<string, unknown> {
  if (!rawJson) return {};
  try {
    const parsed = JSON.parse(rawJson);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

function normalizeString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function copyString(value: unknown, assign: (value: string) => void): void {
  const normalized = normalizeString(value);
  if (normalized) assign(normalized);
}
