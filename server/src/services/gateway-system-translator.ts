import type { GatewayManageService } from './gateway-manage-service.js';
import type {
  SkillTranslationJobContext,
  SkillTranslationSource,
  SkillTranslator,
} from './skill-translation-service.js';

type GatewayManageLike = Pick<GatewayManageService, 'getSystemSession'>;

const DESCRIPTION_SCHEMA = {
  type: 'object',
  required: ['description'],
  properties: {
    description: { type: 'string' },
  },
};

export function createGatewaySystemSkillTranslator(
  gatewayManageService: GatewayManageLike,
): SkillTranslator {
  return async (
    source: SkillTranslationSource,
    locale: string,
    context: SkillTranslationJobContext,
  ) => {
    const description = source.description?.trim();
    if (!description) return {};

    const session = gatewayManageService.getSystemSession(context.gatewayId);
    const response = await session.request({
      internal: true,
      purpose: 'translation',
      prompt: buildDescriptionPrompt(description, locale),
      responseSchema: DESCRIPTION_SCHEMA,
      metadata: {
        source: 'translation',
        entity_type: 'skill',
        entity_id: context.skillId,
        locale,
        field_set: context.fieldSet,
        source_hash: context.sourceHash,
        job_id: context.jobId,
      },
    });

    if (!response.ok) {
      throw new Error(response.errorMessage || response.errorCode || 'Gateway system translation failed.');
    }

    const translated = extractDescription(response.json, response.text);
    if (!translated) {
      const keys = response.json && typeof response.json === 'object'
        ? Object.keys(response.json as Record<string, unknown>).join(',')
        : '';
      console.warn(
        `[SkillTranslation] schema invalid job=${context.jobId} gateway=${context.gatewayId} error=missing_description jsonKeys=${keys} fallback=source`,
      );
      throw new Error('Skill translation response did not include description.');
    }

    console.log(
      `[SkillTranslation] schema ok job=${context.jobId} gateway=${context.gatewayId} jsonKeys=description`,
    );
    return { description: translated };
  };
}

function buildDescriptionPrompt(description: string, locale: string): string {
  return [
    `Translate the following skill description to ${locale}.`,
    'Return strict JSON only.',
    'Do not translate skill names, CLI names, file extensions, product names, or code terms.',
    'Return exactly:',
    '{"description":"..."}',
    '',
    'Source:',
    description,
  ].join('\n');
}

function extractDescription(json: unknown, text: string | undefined): string | null {
  const fromJson = descriptionFromObject(json);
  if (fromJson) return fromJson;

  if (!text) return null;
  try {
    return descriptionFromObject(JSON.parse(text));
  } catch {
    return null;
  }
}

function descriptionFromObject(value: unknown): string | null {
  if (!value || typeof value !== 'object') return null;
  const description = (value as { description?: unknown }).description;
  return typeof description === 'string' && description.trim()
    ? description.trim()
    : null;
}
