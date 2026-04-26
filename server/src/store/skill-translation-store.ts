import { randomUUID } from 'node:crypto';
import type BetterSqlite3 from 'better-sqlite3';
import type { Database } from './database.js';
import type {
  SkillTranslationCache,
  SkillTranslationJob,
  SkillTranslationKey,
} from '../types/skill-translation.js';

type CacheRow = SkillTranslationCache;
type JobRow = SkillTranslationJob;

export class SkillTranslationStore {
  private db: BetterSqlite3.Database;

  constructor(database: Database) {
    this.db = database.raw;
  }

  getReadyCache(key: SkillTranslationKey): SkillTranslationCache | null {
    const row = this.db.prepare(`
      SELECT *
      FROM skill_translation_cache
      WHERE gateway_type = ?
        AND gateway_id = ?
        AND skill_id = ?
        AND locale = ?
        AND field_set = ?
        AND source_hash = ?
        AND status = 'ready'
    `).get(
      key.gateway_type,
      key.gateway_id,
      key.skill_id,
      key.locale,
      key.field_set,
      key.source_hash,
    ) as CacheRow | undefined;
    return row ?? null;
  }

  upsertCache(cache: SkillTranslationCache): void {
    const now = Date.now();
    this.db.prepare(`
      INSERT INTO skill_translation_cache (
        gateway_type, gateway_id, skill_id, locale, field_set, source_hash,
        translated_name, translated_description, translated_trigger, translated_body,
        status, error_code, error_message, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(gateway_type, gateway_id, skill_id, locale, field_set, source_hash)
      DO UPDATE SET
        translated_name = excluded.translated_name,
        translated_description = excluded.translated_description,
        translated_trigger = excluded.translated_trigger,
        translated_body = excluded.translated_body,
        status = excluded.status,
        error_code = excluded.error_code,
        error_message = excluded.error_message,
        updated_at = excluded.updated_at
    `).run(
      cache.gateway_type,
      cache.gateway_id,
      cache.skill_id,
      cache.locale,
      cache.field_set,
      cache.source_hash,
      cache.translated_name ?? null,
      cache.translated_description ?? null,
      cache.translated_trigger ?? null,
      cache.translated_body ?? null,
      cache.status,
      cache.error_code ?? null,
      cache.error_message ?? null,
      now,
      now,
    );
  }

  enqueueJob(key: SkillTranslationKey, sourceJson?: string): string {
    const now = Date.now();
    const existing = this.db.prepare(`
      SELECT job_id
      FROM skill_translation_jobs
      WHERE gateway_type = ?
        AND gateway_id = ?
        AND skill_id = ?
        AND locale = ?
        AND field_set = ?
        AND source_hash = ?
        AND status IN ('pending', 'running')
    `).get(
      key.gateway_type,
      key.gateway_id,
      key.skill_id,
      key.locale,
      key.field_set,
      key.source_hash,
    ) as { job_id: string } | undefined;
    if (existing) return existing.job_id;

    const jobId = randomUUID();
    this.db.prepare(`
      INSERT INTO skill_translation_jobs (
        job_id, gateway_type, gateway_id, skill_id, locale, field_set, source_hash,
        source_json, status, attempt_count, last_error, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, NULL, ?, ?)
      ON CONFLICT(gateway_type, gateway_id, skill_id, locale, field_set, source_hash)
      DO UPDATE SET
        source_json = excluded.source_json,
        status = CASE
          WHEN skill_translation_jobs.status IN ('pending', 'running')
          THEN skill_translation_jobs.status
          ELSE 'pending'
        END,
        updated_at = excluded.updated_at
    `).run(
      jobId,
      key.gateway_type,
      key.gateway_id,
      key.skill_id,
      key.locale,
      key.field_set,
      key.source_hash,
      sourceJson ?? null,
      now,
      now,
    );

    const row = this.db.prepare(`
      SELECT job_id
      FROM skill_translation_jobs
      WHERE gateway_type = ?
        AND gateway_id = ?
        AND skill_id = ?
        AND locale = ?
        AND field_set = ?
        AND source_hash = ?
    `).get(
      key.gateway_type,
      key.gateway_id,
      key.skill_id,
      key.locale,
      key.field_set,
      key.source_hash,
    ) as { job_id: string } | undefined;
    return row?.job_id ?? jobId;
  }

  nextPendingJob(): SkillTranslationJob | null {
    const row = this.db.prepare(`
      SELECT *
      FROM skill_translation_jobs
      WHERE status = 'pending'
      ORDER BY created_at ASC
      LIMIT 1
    `).get() as JobRow | undefined;
    return row ?? null;
  }

  markJobRunning(jobId: string): void {
    this.db.prepare(`
      UPDATE skill_translation_jobs
      SET status = 'running',
          attempt_count = attempt_count + 1,
          updated_at = ?
      WHERE job_id = ?
    `).run(Date.now(), jobId);
  }

  markJobReady(jobId: string): void {
    this.db.prepare(`
      UPDATE skill_translation_jobs
      SET status = 'ready',
          updated_at = ?
      WHERE job_id = ?
    `).run(Date.now(), jobId);
  }

  markJobFailed(jobId: string, error: string): void {
    this.db.prepare(`
      UPDATE skill_translation_jobs
      SET status = 'failed',
          last_error = ?,
          updated_at = ?
      WHERE job_id = ?
    `).run(error, Date.now(), jobId);
  }
}
