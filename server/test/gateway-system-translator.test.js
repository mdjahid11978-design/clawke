const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

describe('Gateway system translator', () => {
  it('uses gateway system session and returns only translated description', async () => {
    const { createGatewaySystemSkillTranslator } = require('../dist/services/gateway-system-translator');
    const calls = [];
    const translator = createGatewaySystemSkillTranslator({
      getSystemSession(gatewayId) {
        calls.push({ type: 'getSystemSession', gatewayId });
        return {
          gatewayId,
          sessionId: `__clawke_system__:${gatewayId}`,
          kind: 'system',
          async request(input) {
            calls.push({ type: 'request', input });
            return {
              ok: true,
              json: {
                name: '不应返回',
                description: '设置并使用 1Password CLI。',
              },
            };
          },
        };
      },
    });

    const result = await translator(
      { description: 'Set up and use 1Password CLI (op).' },
      'zh',
      {
        jobId: 'tr_1',
        gatewayType: 'openclaw',
        gatewayId: 'OpenClaw',
        skillId: 'openclaw-bundled/1password',
        locale: 'zh',
        fieldSet: 'metadata',
        sourceHash: 'sha256:a',
      },
    );

    assert.deepEqual(result, { description: '设置并使用 1Password CLI。' });
    assert.deepEqual(calls[0], { type: 'getSystemSession', gatewayId: 'OpenClaw' });
    assert.equal(calls[1].input.internal, true);
    assert.equal(calls[1].input.purpose, 'translation');
    assert.match(calls[1].input.prompt, /Return strict JSON only/);
    assert.match(calls[1].input.prompt, /Set up and use 1Password CLI/);
    assert.deepEqual(calls[1].input.responseSchema, {
      type: 'object',
      required: ['description'],
      properties: {
        description: { type: 'string' },
      },
    });
    assert.deepEqual(calls[1].input.metadata, {
      source: 'translation',
      entity_type: 'skill',
      entity_id: 'openclaw-bundled/1password',
      locale: 'zh',
      field_set: 'metadata',
      source_hash: 'sha256:a',
      job_id: 'tr_1',
    });
  });

  it('does not require OpenAI translation environment variables', async () => {
    const { createGatewaySystemSkillTranslator } = require('../dist/services/gateway-system-translator');
    const oldOpenAI = process.env.OPENAI_API_KEY;
    const oldClawke = process.env.CLAWKE_TRANSLATION_API_KEY;
    delete process.env.OPENAI_API_KEY;
    delete process.env.CLAWKE_TRANSLATION_API_KEY;
    try {
      const translator = createGatewaySystemSkillTranslator({
        getSystemSession(gatewayId) {
          return {
            gatewayId,
            sessionId: `__clawke_system__:${gatewayId}`,
            kind: 'system',
            async request() {
              return { ok: true, json: { description: '中文描述' } };
            },
          };
        },
      });

      const result = await translator(
        { description: 'English description' },
        'zh',
        {
          jobId: 'tr_2',
          gatewayType: 'hermes',
          gatewayId: 'Hermes',
          skillId: 'general/example',
          locale: 'zh',
          fieldSet: 'metadata',
          sourceHash: 'sha256:b',
        },
      );

      assert.deepEqual(result, { description: '中文描述' });
    } finally {
      if (oldOpenAI) process.env.OPENAI_API_KEY = oldOpenAI;
      if (oldClawke) process.env.CLAWKE_TRANSLATION_API_KEY = oldClawke;
    }
  });

  it('rejects invalid gateway JSON', async () => {
    const { createGatewaySystemSkillTranslator } = require('../dist/services/gateway-system-translator');
    const translator = createGatewaySystemSkillTranslator({
      getSystemSession(gatewayId) {
        return {
          gatewayId,
          sessionId: `__clawke_system__:${gatewayId}`,
          kind: 'system',
          async request() {
            return { ok: true, json: { message: 'missing description' } };
          },
        };
      },
    });

    await assert.rejects(
      () => translator(
        { description: 'English description' },
        'zh',
        {
          jobId: 'tr_3',
          gatewayType: 'nanobot',
          gatewayId: 'nanobot',
          skillId: 'general/example',
          locale: 'zh',
          fieldSet: 'metadata',
          sourceHash: 'sha256:c',
        },
      ),
      /description/,
    );
  });
});
