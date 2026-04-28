import type { GatewayManageService } from './gateway-manage-service.js';
import type {
  SkillTranslationBatchItem,
  SkillTranslationSource,
  SkillTranslator,
} from './skill-translation-service.js';

type GatewayManageLike = Pick<GatewayManageService, 'getSystemSession'>;

const DESCRIPTION_SCHEMA = {
  type: 'object',
  required: ['items'],
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'description'],
        properties: {
          id: { type: 'string' },
          description: { type: 'string' },
        },
      },
    },
  },
};

const MAX_DESCRIPTION_CHARS = 200;
const TRANSLATION_TIMEOUT_MS = 5 * 60 * 1000;

export function createGatewaySystemSkillTranslator(
  gatewayManageService: GatewayManageLike,
): SkillTranslator {
  return async (
    items: SkillTranslationBatchItem[],
    locale: string,
  ) => {
    const translatableItems = items.filter((item) => item.source.description?.trim());
    if (translatableItems.length === 0) return new Map();

    const first = translatableItems[0];
    const session = gatewayManageService.getSystemSession(first.gatewayId);
    const response = await session.request({
      internal: true,
      purpose: 'translation',
      timeoutMs: TRANSLATION_TIMEOUT_MS,
      prompt: buildDescriptionPrompt(translatableItems, locale),
      responseSchema: DESCRIPTION_SCHEMA,
      metadata: {
        source: 'translation',
        entity_type: 'skill',
        locale,
        field_set: first.fieldSet,
        item_count: translatableItems.length,
        job_ids: translatableItems.map((item) => item.jobId),
      },
    });

    if (!response.ok) {
      throw new Error(response.errorMessage || response.errorCode || 'Gateway system translation failed.');
    }

    const translatedItems = extractItems(response.json, response.text);
    const results = new Map<string, { description: string }>();
    const inputById = new Map(translatableItems.map((item) => [item.jobId, item]));
    for (const translated of translatedItems) {
      const sourceItem = inputById.get(translated.id);
      if (!sourceItem) {
        console.warn(
          `[SkillTranslation] schema ignored_unknown_id gateway=${first.gatewayId} id=${translated.id}`,
        );
        continue;
      }
      const description = translated.description.trim();
      if (description) {
        results.set(sourceItem.jobId, { description });
      }
    }

    if (results.size === 0) {
      const keys = response.json && typeof response.json === 'object'
        ? Object.keys(response.json as Record<string, unknown>).join(',')
        : '';
      console.warn(
        `[SkillTranslation] schema invalid gateway=${first.gatewayId} error=missing_description jsonKeys=${keys} fallback=source`,
      );
      throw new Error('Skill translation response did not include description.');
    }

    console.log(
      `[SkillTranslation] schema ok gateway=${first.gatewayId} jsonKeys=items translated=${results.size}/${translatableItems.length}`,
    );
    return results;
  };
}

function buildDescriptionPrompt(items: SkillTranslationBatchItem[], locale: string): string {
  const payload = items.map((item) => ({
    id: item.jobId,
    description: truncateDescription(item.source.description ?? ''),
  }));
  return [
    `Translate the following skill descriptions to ${locale}.`,
    'Return strict JSON only.',
    'Keep each returned id exactly the same as the input id.',
    'Do not translate skill names, CLI names, file extensions, product names, or code terms.',
    'Return exactly:',
    '{"items":[{"id":"same input id","description":"..."}]}',
    '',
    'Source items:',
    JSON.stringify(payload),
  ].join('\n');
}

function truncateDescription(description: string): string {
  const trimmed = description.trim();
  return trimmed.length > MAX_DESCRIPTION_CHARS
    ? trimmed.slice(0, MAX_DESCRIPTION_CHARS)
    : trimmed;
}

function extractItems(json: unknown, text: string | undefined): Array<{ id: string; description: string }> {
  const fromJson = itemsFromObject(json);
  if (fromJson.length > 0) return fromJson;

  if (!text) return [];
  try {
    return itemsFromObject(JSON.parse(text));
  } catch {
    return [];
  }
}

function itemsFromObject(value: unknown): Array<{ id: string; description: string }> {
  if (!value || typeof value !== 'object') return [];
  const items = (value as { items?: unknown }).items;
  if (!Array.isArray(items)) return [];
  return items.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const id = (item as { id?: unknown }).id;
    const description = (item as { description?: unknown }).description;
    return typeof id === 'string' && typeof description === 'string' && description.trim()
      ? [{ id, description }]
      : [];
  });
}
