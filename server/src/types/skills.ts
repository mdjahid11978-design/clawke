import type { SkillLocalizationPayload } from './skill-translation.js';

export interface SkillScope {
  id: string;
  type: 'gateway';
  label: string;
  description: string;
  readonly: boolean;
  gatewayId: string;
}

export interface ManagedSkill {
  id: string;
  name: string;
  description: string;
  category: string;
  trigger?: string;
  enabled: boolean;
  source: 'managed' | 'external' | 'readonly';
  sourceLabel: string;
  writable: boolean;
  deletable: boolean;
  path: string;
  absolutePath?: string;
  root: string;
  updatedAt: number;
  hasConflict: boolean;
  content?: string;
  body?: string;
  frontmatter?: Record<string, unknown>;
  sourceHash?: string;
  localization?: SkillLocalizationPayload;
}

export interface SkillDraft {
  name: string;
  category?: string;
  description: string;
  trigger?: string;
  body?: string;
  content?: string;
}

export type SkillGatewayRequest =
  | { type: 'skill_list'; request_id?: string; account_id: string }
  | { type: 'skill_get'; request_id?: string; account_id: string; skill_id: string }
  | { type: 'skill_create'; request_id?: string; account_id: string; skill: SkillDraft }
  | { type: 'skill_update'; request_id?: string; account_id: string; skill_id: string; skill: SkillDraft }
  | { type: 'skill_delete'; request_id?: string; account_id: string; skill_id: string }
  | { type: 'skill_set_enabled'; request_id?: string; account_id: string; skill_id: string; enabled: boolean };

export interface SkillGatewayResponse {
  type: 'skill_list_response' | 'skill_get_response' | 'skill_mutation_response';
  request_id: string;
  ok?: boolean;
  error?: string;
  message?: string;
  details?: unknown;
  skills?: ManagedSkill[];
  skill?: ManagedSkill;
  deleted?: boolean;
}
