/** Gateway-scoped Skills REST API. */
import type { Request, Response } from 'express';
import type { SkillDraft, SkillGatewayRequest, SkillGatewayResponse, SkillScope, ManagedSkill } from '../types/skills.js';
import type { SkillLocalizationPayload, SkillTranslationFieldSet } from '../types/skill-translation.js';
import type { SkillTranslationService, SkillTranslationSource } from '../services/skill-translation-service.js';
import { hashSkillTranslationSource } from '../services/skill-translation-service.js';
import { sendSkillGatewayRequest, SkillGatewayError } from '../upstream/skill-gateway-client.js';

interface SkillsRouteDeps {
  getConnectedAccountIds: () => string[];
  sendSkillRequest?: (payload: SkillGatewayRequest) => Promise<SkillGatewayResponse>;
  translationService?: Pick<SkillTranslationService, 'getOrQueue'>;
}

let deps: SkillsRouteDeps | null = null;

export function initSkillsRoutes(nextDeps: SkillsRouteDeps): void {
  deps = nextDeps;
}

export async function listSkillScopes(_req: Request, res: Response): Promise<void> {
  const ids = deps?.getConnectedAccountIds() || [];
  const scopes: SkillScope[] = ids.map((gatewayId) => ({
    id: `gateway:${gatewayId}`,
    type: 'gateway',
    label: gatewayId,
    description: 'Gateway',
    readonly: false,
    gatewayId,
  }));
  res.json({ scopes });
}

export async function listSkills(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  const locale = resolveLocale(req);
  await respond(res, { type: 'skill_list', account_id: accountId }, (response) => ({
    skills: (response.skills || []).map((skill) => localizeSkill(skill, accountId, locale, 'metadata')),
  }));
}

export async function getSkill(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  const locale = resolveLocale(req);
  await respond(res, {
    type: 'skill_get',
    account_id: accountId,
    skill_id: skillIdFromParams(req),
  }, (response) => ({
    skill: response.skill
      ? localizeSkill(response.skill, accountId, locale, 'detail')
      : response.skill,
  }));
}

export async function createSkill(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  const draft = req.body as SkillDraft;
  const validation = validateDraft(draft);
  if (validation) {
    sendHttpError(res, 400, 'validation_error', validation);
    return;
  }
  await respond(res, {
    type: 'skill_create',
    account_id: accountId,
    skill: draft,
  }, (response) => ({ skill: response.skill }), 201);
}

export async function updateSkill(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  const draft = req.body as SkillDraft;
  const validation = validateDraft(draft);
  if (validation) {
    sendHttpError(res, 400, 'validation_error', validation);
    return;
  }
  await respond(res, {
    type: 'skill_update',
    account_id: accountId,
    skill_id: skillIdFromParams(req),
    skill: draft,
  }, (response) => ({ skill: response.skill }));
}

export async function setSkillEnabled(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  if (typeof req.body?.enabled !== 'boolean') {
    sendHttpError(res, 400, 'validation_error', 'enabled must be a boolean.');
    return;
  }
  await respond(res, {
    type: 'skill_set_enabled',
    account_id: accountId,
    skill_id: skillIdFromParams(req),
    enabled: req.body.enabled,
  }, (response) => ({ ok: true, skill: response.skill }));
}

export async function deleteSkill(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, {
    type: 'skill_delete',
    account_id: accountId,
    skill_id: skillIdFromParams(req),
  }, (response) => ({ ok: true, deleted: response.deleted !== false }));
}

function resolveAccountId(req: Request, res: Response): string | null {
  const explicit = singleQueryValue(req.query.gateway_id)
    || singleQueryValue(req.query.account_id)
    || stringValue(req.body?.gateway_id)
    || stringValue(req.body?.account_id);
  if (explicit) return explicit;

  const connected = deps?.getConnectedAccountIds() || [];
  if (connected.length === 1) return connected[0];

  sendHttpError(res, 400, 'account_required', 'gateway_id is required when gateway selection is ambiguous.');
  return null;
}

function skillIdFromParams(req: Request): string {
  return `${req.params.category}/${req.params.name}`;
}

function validateDraft(draft: SkillDraft | undefined): string | null {
  if (!draft || typeof draft !== 'object') return 'skill draft is required.';
  if (typeof draft.name !== 'string' || !draft.name.trim()) return 'name is required.';
  if (typeof draft.description !== 'string' || !draft.description.trim()) return 'description is required.';
  return null;
}

type LocalizedSkill = ManagedSkill & {
  sourceHash?: string;
  localization?: SkillLocalizationPayload;
};

function localizeSkill(
  skill: ManagedSkill,
  accountId: string,
  locale: string | undefined,
  fieldSet: SkillTranslationFieldSet,
): LocalizedSkill {
  const source = translationSource(skill, fieldSet);
  const sourceHash = hashSkillTranslationSource(source);
  const localization = descriptionOnlyLocalization(deps?.translationService?.getOrQueue({
    gatewayType: accountId,
    gatewayId: accountId,
    skillId: skill.id,
    locale,
    fieldSet,
    sourceHash,
    source,
  }));
  return {
    ...skill,
    sourceHash,
    ...(localization ? { localization } : {}),
  };
}

function translationSource(
  skill: ManagedSkill,
  _fieldSet: SkillTranslationFieldSet,
): SkillTranslationSource {
  return {
    description: skill.description,
  };
}

function descriptionOnlyLocalization(
  localization: SkillLocalizationPayload | undefined,
): SkillLocalizationPayload | undefined {
  if (!localization) return undefined;
  return {
    locale: localization.locale,
    status: localization.status,
    ...(localization.description ? { description: localization.description } : {}),
    ...(localization.error ? { error: localization.error } : {}),
  };
}

async function respond(
  res: Response,
  request: SkillGatewayRequest,
  map: (response: SkillGatewayResponse) => Record<string, unknown>,
  status = 200,
): Promise<void> {
  try {
    const sender = deps?.sendSkillRequest || sendSkillGatewayRequest;
    const response = await sender(request);
    res.status(status).json(map(response));
  } catch (err) {
    if (err instanceof SkillGatewayError) {
      sendHttpError(res, err.status, err.code, err.message, err.details);
      return;
    }
    const message = err instanceof Error ? err.message : String(err);
    sendHttpError(res, 500, 'internal_error', message);
  }
}

function singleQueryValue(value: unknown): string | undefined {
  if (Array.isArray(value)) {
    return typeof value[0] === 'string' ? value[0] : undefined;
  }
  return typeof value === 'string' ? value : undefined;
}

function resolveLocale(req: Request): string | undefined {
  return singleQueryValue(req.query.locale) || stringValue(req.body?.locale);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value : undefined;
}

function sendHttpError(res: Response, status: number, error: string, message: string, details?: unknown): void {
  res.status(status).json({ error, message, ...(details === undefined ? {} : { details }) });
}
