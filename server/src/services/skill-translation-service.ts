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

export type SkillTranslator = (
  source: SkillTranslationSource,
  locale: string,
  context: SkillTranslationJobContext,
) => Promise<Pick<Partial<SkillLocalizationPayload>, 'description'>>;

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
    const job = this.options.store.nextPendingJob();
    if (!job) return false;

    this.options.store.markJobRunning(job.job_id);
    try {
      console.log(
        `[SkillTranslation] job started job=${job.job_id} attempt=${job.attempt_count + 1} backend=gateway_system gateway=${job.gateway_id} locale=${job.locale} sourceHash=${job.source_hash}`,
      );
      const source = parseSource(job.source_json);
      const translated = await this.options.translator(source, job.locale, {
        jobId: job.job_id,
        gatewayType: job.gateway_type,
        gatewayId: job.gateway_id,
        skillId: job.skill_id,
        locale: job.locale,
        fieldSet: job.field_set,
        sourceHash: job.source_hash,
      });
      this.options.store.upsertCache({
        gateway_type: job.gateway_type,
        gateway_id: job.gateway_id,
        skill_id: job.skill_id,
        locale: job.locale,
        field_set: job.field_set,
        source_hash: job.source_hash,
        translated_name: null,
        translated_description: translated.description ?? null,
        translated_trigger: null,
        translated_body: null,
        status: 'ready',
      });
      this.options.store.markJobReady(job.job_id);
      console.log(
        `[SkillTranslation] cache ready job=${job.job_id} gateway=${job.gateway_id} entity=skill:${job.skill_id} locale=${job.locale} sourceHash=${job.source_hash} translatedDescriptionLength=${translated.description?.length ?? 0}`,
      );
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.options.store.markJobFailed(
        job.job_id,
        message,
      );
      console.warn(
        `[SkillTranslation] cache failed job=${job.job_id} gateway=${job.gateway_id} entity=skill:${job.skill_id} locale=${job.locale} sourceHash=${job.source_hash} error=${message} fallback=source`,
      );
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
