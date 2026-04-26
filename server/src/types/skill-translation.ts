export type SkillTranslationStatus = 'missing' | 'pending' | 'running' | 'ready' | 'failed';
export type SkillTranslationFieldSet = 'metadata' | 'detail';

export interface SkillTranslationKey {
  gateway_type: string;
  gateway_id: string;
  skill_id: string;
  locale: string;
  field_set: SkillTranslationFieldSet;
  source_hash: string;
}

export interface SkillTranslationCache extends SkillTranslationKey {
  translated_name?: string | null;
  translated_description?: string | null;
  translated_trigger?: string | null;
  translated_body?: string | null;
  status: SkillTranslationStatus;
  error_code?: string | null;
  error_message?: string | null;
}

export interface SkillTranslationJob extends SkillTranslationKey {
  job_id: string;
  status: SkillTranslationStatus;
  attempt_count: number;
  last_error?: string | null;
  source_json?: string | null;
}

export interface SkillLocalizationPayload {
  locale: string;
  status: SkillTranslationStatus;
  name?: string | null;
  description?: string | null;
  trigger?: string | null;
  body?: string | null;
  error?: string | null;
}
