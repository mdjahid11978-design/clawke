import type { SkillTranslationSource, SkillTranslator } from './skill-translation-service.js';

type FetchLike = typeof fetch;

interface OpenAiTranslatorOptions {
  apiKey: string;
  model: string;
  baseUrl?: string;
  fetchFn?: FetchLike;
}

export function createConfiguredSkillTranslator(
  env: NodeJS.ProcessEnv = process.env,
  fetchFn: FetchLike = fetch,
): SkillTranslator {
  const apiKey = env.CLAWKE_TRANSLATION_API_KEY || env.OPENAI_API_KEY;
  if (!apiKey) {
    return async () => {
      throw new Error('Skill translation requires OPENAI_API_KEY or CLAWKE_TRANSLATION_API_KEY.');
    };
  }

  return createOpenAiSkillTranslator({
    apiKey,
    model: env.CLAWKE_TRANSLATION_MODEL || env.OPENAI_TRANSLATION_MODEL || env.OPENAI_MODEL || 'gpt-4o-mini',
    baseUrl: env.CLAWKE_TRANSLATION_BASE_URL || env.OPENAI_BASE_URL,
    fetchFn,
  });
}

export function createOpenAiSkillTranslator(options: OpenAiTranslatorOptions): SkillTranslator {
  const baseUrl = (options.baseUrl || 'https://api.openai.com/v1').replace(/\/+$/, '');
  const fetchFn = options.fetchFn || fetch;

  return async (source: SkillTranslationSource, locale: string) => {
    const description = source.description?.trim();
    if (!description) return {};

    const response = await fetchFn(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${options.apiKey}`,
      },
      body: JSON.stringify({
        model: options.model,
        temperature: 0,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content: [
              'Translate only the provided skill description to the requested target locale.',
              'If the description is already written in the target locale, return it unchanged.',
              'Do not translate or output skill names.',
              'Preserve product names, CLI names, file extensions, and code terms.',
              'Return strict JSON with exactly one key: description.',
            ].join(' '),
          },
          {
            role: 'user',
            content: JSON.stringify({
              locale,
              description,
            }),
          },
        ],
      }),
    });

    if (!response.ok) {
      throw new Error(`Skill translation request failed: HTTP ${response.status} ${await safeText(response)}`);
    }

    const payload = await response.json() as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const content = payload.choices?.[0]?.message?.content;
    const translated = parseDescription(content);
    if (!translated) {
      throw new Error('Skill translation response did not include description.');
    }
    return { description: translated };
  };
}

async function safeText(response: Response): Promise<string> {
  try {
    return (await response.text()).slice(0, 500);
  } catch {
    return '';
  }
}

function parseDescription(content: string | undefined): string | null {
  if (!content) return null;
  try {
    const parsed = JSON.parse(content) as unknown;
    if (!parsed || typeof parsed !== 'object') return null;
    const description = (parsed as { description?: unknown }).description;
    return typeof description === 'string' && description.trim()
      ? description.trim()
      : null;
  } catch {
    return null;
  }
}
