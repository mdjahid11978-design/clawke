import type BetterSqlite3 from 'better-sqlite3';
import type { Database } from './database.js';
import type { GatewayInfo, GatewayStatus } from '../types/gateways.js';

type GatewayRow = {
  gateway_id: string;
  display_name: string | null;
  gateway_type: string | null;
  status: string;
  capabilities_json: string;
  last_error_code: string | null;
  last_error_message: string | null;
  last_connected_at: number | null;
  last_seen_at: number | null;
};

export class GatewayStore {
  private db: BetterSqlite3.Database;

  constructor(database: Database) {
    this.db = database.raw;
  }

  get(gatewayId: string): GatewayInfo | null {
    const row = this.db
      .prepare('SELECT * FROM gateway_metadata WHERE gateway_id = ?')
      .get(gatewayId) as GatewayRow | undefined;
    return row ? this.toInfo(row) : null;
  }

  list(): GatewayInfo[] {
    const rows = this.db
      .prepare('SELECT * FROM gateway_metadata ORDER BY display_name COLLATE NOCASE, gateway_id')
      .all() as GatewayRow[];
    return rows.map((row) => this.toInfo(row));
  }

  upsertRuntime(info: GatewayInfo): void {
    const existing = this.get(info.gateway_id);
    const displayName = existing?.display_name || info.display_name || info.gateway_id;
    const now = Date.now();
    this.db.prepare(`
      INSERT INTO gateway_metadata (
        gateway_id, display_name, gateway_type, status, capabilities_json,
        last_error_code, last_error_message, last_connected_at, last_seen_at,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(gateway_id) DO UPDATE SET
        display_name = excluded.display_name,
        gateway_type = excluded.gateway_type,
        status = excluded.status,
        capabilities_json = excluded.capabilities_json,
        last_error_code = excluded.last_error_code,
        last_error_message = excluded.last_error_message,
        last_connected_at = excluded.last_connected_at,
        last_seen_at = excluded.last_seen_at,
        updated_at = excluded.updated_at
    `).run(
      info.gateway_id,
      displayName,
      info.gateway_type,
      info.status,
      JSON.stringify(info.capabilities),
      info.last_error_code ?? null,
      info.last_error_message ?? null,
      info.last_connected_at ?? null,
      info.last_seen_at ?? null,
      now,
      now,
    );
  }

  rename(gatewayId: string, displayName: string): boolean {
    const result = this.db
      .prepare('UPDATE gateway_metadata SET display_name = ?, updated_at = ? WHERE gateway_id = ?')
      .run(displayName, Date.now(), gatewayId);
    return result.changes > 0;
  }

  deleteMissing(serverIds: string[]): void {
    const ids = new Set(serverIds);
    for (const item of this.list()) {
      if (!ids.has(item.gateway_id)) {
        this.db.prepare('DELETE FROM gateway_metadata WHERE gateway_id = ?').run(item.gateway_id);
      }
    }
  }

  private toInfo(row: GatewayRow): GatewayInfo {
    return {
      gateway_id: row.gateway_id,
      display_name: row.display_name || row.gateway_id,
      gateway_type: row.gateway_type || 'unknown',
      status: normalizeStatus(row.status),
      capabilities: parseCapabilities(row.capabilities_json),
      last_error_code: row.last_error_code,
      last_error_message: row.last_error_message,
      last_connected_at: row.last_connected_at,
      last_seen_at: row.last_seen_at,
    };
  }
}

function normalizeStatus(value: string): GatewayStatus {
  if (value === 'online' || value === 'error') return value;
  return 'disconnected';
}

function parseCapabilities(raw: string): string[] {
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed.map((item) => String(item)).filter(Boolean);
  } catch {
    return [];
  }
}
