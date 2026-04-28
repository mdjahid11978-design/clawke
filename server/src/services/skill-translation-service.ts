import { createHash } from 'node:crypto';
import type { SkillTranslationStore } from '../store/skill-translation-store.js';
import type {
  SkillLocalizationPayload,
  SkillTranslationFieldSet,
  SkillTranslationKey,
} from '../types/skill-translation.js';

export type SkillTranslationSource = {
  description?: string;
};

export interface SkillTranslationJobContext {
  jobId: string;
  gatewayType: string;
  gatewayId: string;
  skillId: string;
  locale: string;
  fieldSet: SkillTranslationFieldSet;
  sourceHash: string;
}

export interface SkillTranslationBatchItem extends SkillTranslationJobContext {
  source: SkillTranslationSource;
}

export type SkillTranslator = (
  items: SkillTranslationBatchItem[],
  locale: string,
) => Promise<Map<string, Pick<Partial<SkillLocalizationPayload>, 'description'>>>;

export interface SkillTranslationLookupInput {
  gatewayType: string;
  gatewayId: string;
  skillId: string;
  locale?: string;
  fieldSet: SkillTranslationFieldSet;
  sourceHash?: string;
  source: SkillTranslationSource;
}

export class SkillTranslationService {
  constructor(
    private readonly options: {
      store: SkillTranslationStore;
      translator: SkillTranslator;
      batchSize?: number;
    },
  ) {}

  getOrQueue(input: SkillTranslationLookupInput): SkillLocalizationPayload {
    const locale = input.locale?.trim();
    if (!locale || locale.toLowerCase() === 'en') {
      return { locale: locale || '', status: 'missing' };
    }

    const sourceDescription = input.source.description?.trim();
    if (isAlreadyInTargetLocale(sourceDescription, locale)) {
      return {
        locale,
        status: 'ready',
        description: sourceDescription,
      };
    }

    const key = this.toKey(input, locale);
    const cache = this.options.store.getReadyCache(key);
    if (cache) {
      return {
        locale,
        status: 'ready',
        description: cache.translated_description,
      };
    }

    this.options.store.enqueueJob(key, JSON.stringify(input.source));
    return { locale, status: 'pending' };
  }

  async runNextJob(): Promise<boolean> {
    const jobs = this.options.store.nextPendingJobs(this.options.batchSize ?? 25);
    if (jobs.length === 0) return false;

    const jobIds = jobs.map((job) => job.job_id);
    this.options.store.markJobsRunning(jobIds);
    try {
      const firstJob = jobs[0];
      console.log(
        `[SkillTranslation] batch started jobs=${jobs.length} firstJob=${firstJob.job_id} backend=gateway_system gateway=${firstJob.gateway_id} locale=${firstJob.locale}`,
      );
      const items = jobs.map((job): SkillTranslationBatchItem => ({
        jobId: job.job_id,
        gatewayType: job.gateway_type,
        gatewayId: job.gateway_id,
        skillId: job.skill_id,
        locale: job.locale,
        fieldSet: job.field_set,
        sourceHash: job.source_hash,
        source: parseSource(job.source_json),
      }));
      const translatedByJobId = await this.options.translator(items, firstJob.locale);
      let readyCount = 0;
      let failedCount = 0;
      for (const job of jobs) {
        const translated = translatedByJobId.get(job.job_id);
        if (!translated?.description) {
          failedCount += 1;
          this.options.store.markJobFailed(job.job_id, 'Skill translation response did not include description.');
          console.warn(
            `[SkillTranslation] cache failed job=${job.job_id} gateway=${job.gateway_id} entity=skill:${job.skill_id} locale=${job.locale} sourceHash=${job.source_hash} error=missing_description fallback=source`,
          );
          continue;
        }
        this.options.store.upsertCache({
          gateway_type: job.gateway_type,
          gateway_id: job.gateway_id,
          skill_id: job.skill_id,
          locale: job.locale,
          field_set: job.field_set,
          source_hash: job.source_hash,
          translated_name: null,
          translated_description: translated.description,
          translated_trigger: null,
          translated_body: null,
          status: 'ready',
        });
        this.options.store.markJobReady(job.job_id);
        readyCount += 1;
        console.log(
          `[SkillTranslation] cache ready job=${job.job_id} gateway=${job.gateway_id} entity=skill:${job.skill_id} locale=${job.locale} sourceHash=${job.source_hash} translatedDescriptionLength=${translated.description.length}`,
        );
      }
      console.log(
        `[SkillTranslation] batch finished jobs=${jobs.length} ready=${readyCount} failed=${failedCount} gateway=${firstJob.gateway_id} locale=${firstJob.locale}`,
      );
      return readyCount > 0;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      for (const job of jobs) {
        this.options.store.markJobFailed(job.job_id, message);
        console.warn(
          `[SkillTranslation] cache failed job=${job.job_id} gateway=${job.gateway_id} entity=skill:${job.skill_id} locale=${job.locale} sourceHash=${job.source_hash} error=${message} fallback=source`,
        );
      }
      return false;
    }
  }

  private toKey(
    input: SkillTranslationLookupInput,
    locale: string,
  ): SkillTranslationKey {
    return {
      gateway_type: input.gatewayType,
      gateway_id: input.gatewayId,
      skill_id: input.skillId,
      locale,
      field_set: input.fieldSet,
      source_hash: input.sourceHash || hashSkillTranslationSource(input.source),
    };
  }
}

export function startSkillTranslationWorker(
  service: SkillTranslationService,
  options: { intervalMs?: number; onError?: (error: unknown) => void } = {},
): () => void {
  const intervalMs = options.intervalMs ?? 1000;
  let stopped = false;
  let running = false;

  const tick = async () => {
    if (stopped || running) return;
    running = true;
    try {
      while (!stopped && await service.runNextJob()) {}
    } catch (error) {
      options.onError?.(error);
    } finally {
      running = false;
    }
  };

  const timer = setInterval(() => {
    void tick();
  }, intervalMs);
  void tick();

  return () => {
    stopped = true;
    clearInterval(timer);
  };
}

export function hashSkillTranslationSource(source: SkillTranslationSource): string {
  return createHash('sha256').update(JSON.stringify(source)).digest('hex');
}

function isAlreadyInTargetLocale(text: string | undefined, locale: string): text is string {
  if (!text) return false;
  const normalized = locale.toLowerCase();
  if (normalized === 'zh' || normalized.startsWith('zh-')) {
    return /[\u3400-\u9fff]/.test(text);
  }
  return false;
}

function parseSource(raw: string | null | undefined): SkillTranslationSource {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== 'object') return {};
    return parsed as SkillTranslationSource;
  } catch {
    return {};
  }
}
