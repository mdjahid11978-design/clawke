import type BetterSqlite3 from 'better-sqlite3';
import type { Database } from './database.js';

export type PushPlatform = 'ios' | 'macos' | 'android';
export type PushProvider = 'apns' | 'fcm';

export interface PushDeviceInput {
  deviceId: string;
  userId: string;
  platform: PushPlatform;
  pushProvider: PushProvider;
  deviceToken: string;
  appVersion?: string;
}

export interface PushDevice extends PushDeviceInput {
  enabled: boolean;
  createdAt: number;
  updatedAt: number;
}

type PushDeviceRow = {
  device_id: string;
  user_id: string;
  platform: PushPlatform;
  push_provider: PushProvider;
  device_token: string;
  app_version: string | null;
  enabled: number;
  created_at: number;
  updated_at: number;
};

export class PushDeviceStore {
  private db: BetterSqlite3.Database;

  constructor(database: Database) {
    this.db = database.raw;
  }

  upsert(input: PushDeviceInput): PushDevice {
    const now = Date.now();
    this.db.prepare(`
      INSERT INTO push_devices (
        device_id, push_provider, user_id, platform, device_token,
        app_version, enabled, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
      ON CONFLICT(device_id, push_provider) DO UPDATE SET
        user_id = excluded.user_id,
        platform = excluded.platform,
        device_token = excluded.device_token,
        app_version = excluded.app_version,
        enabled = 1,
        updated_at = excluded.updated_at
    `).run(
      input.deviceId,
      input.pushProvider,
      input.userId,
      input.platform,
      input.deviceToken,
      input.appVersion ?? null,
      now,
      now,
    );
    return this.get(input.deviceId, input.pushProvider) as PushDevice;
  }

  get(deviceId: string, pushProvider: PushProvider): PushDevice | null {
    const row = this.db.prepare(`
      SELECT * FROM push_devices WHERE device_id = ? AND push_provider = ?
    `).get(deviceId, pushProvider) as PushDeviceRow | undefined;
    return row ? this.toDevice(row) : null;
  }

  listEnabled(userId?: string): PushDevice[] {
    const rows = userId
      ? this.db.prepare(`
          SELECT * FROM push_devices
          WHERE enabled = 1 AND user_id = ?
          ORDER BY updated_at DESC
        `).all(userId) as PushDeviceRow[]
      : this.db.prepare(`
          SELECT * FROM push_devices
          WHERE enabled = 1
          ORDER BY updated_at DESC
        `).all() as PushDeviceRow[];
    return rows.map((row) => this.toDevice(row));
  }

  disable(deviceId: string, pushProvider: PushProvider): boolean {
    const result = this.db.prepare(`
      UPDATE push_devices
      SET enabled = 0, updated_at = ?
      WHERE device_id = ? AND push_provider = ?
    `).run(Date.now(), deviceId, pushProvider);
    return result.changes > 0;
  }

  private toDevice(row: PushDeviceRow): PushDevice {
    return {
      deviceId: row.device_id,
      userId: row.user_id,
      platform: row.platform,
      pushProvider: row.push_provider,
      deviceToken: row.device_token,
      appVersion: row.app_version ?? undefined,
      enabled: row.enabled === 1,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }
}
