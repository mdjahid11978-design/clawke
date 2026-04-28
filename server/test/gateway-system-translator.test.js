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
                items: [
                  {
                    id: 'tr_1',
                    name: '不应返回',
                    description: '设置并使用 1Password CLI。',
                  },
                ],
              },
            };
          },
        };
      },
    });

    const result = await translator([
      {
        jobId: 'tr_1',
        gatewayType: 'openclaw',
        gatewayId: 'OpenClaw',
        skillId: 'openclaw-bundled/1password',
        locale: 'zh',
        fieldSet: 'metadata',
        sourceHash: 'sha256:a',
        source: { description: 'Set up and use 1Password CLI (op).' },
      },
    ], 'zh');

    assert.deepEqual(result, new Map([['tr_1', { description: '设置并使用 1Password CLI。' }]]));
    assert.deepEqual(calls[0], { type: 'getSystemSession', gatewayId: 'OpenClaw' });
    assert.equal(calls[1].input.internal, true);
    assert.equal(calls[1].input.purpose, 'translation');
    assert.equal(calls[1].input.timeoutMs, 300000);
    assert.match(calls[1].input.prompt, /Return strict JSON only/);
    assert.match(calls[1].input.prompt, /Set up and use 1Password CLI/);
    assert.deepEqual(calls[1].input.responseSchema, {
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
    });
    assert.deepEqual(calls[1].input.metadata, {
      source: 'translation',
      entity_type: 'skill',
      locale: 'zh',
      field_set: 'metadata',
      item_count: 1,
      job_ids: ['tr_1'],
    });
  });

  it('maps batch results by stable skill id and truncates long descriptions', async () => {
    const { createGatewaySystemSkillTranslator } = require('../dist/services/gateway-system-translator');
    const calls = [];
    const longDescription = `${'A'.repeat(200)}SHOULD_NOT_BE_SENT`;
    const translator = createGatewaySystemSkillTranslator({
      getSystemSession(gatewayId) {
        return {
          gatewayId,
          sessionId: `__clawke_system__:${gatewayId}`,
          kind: 'system',
          async request(input) {
            calls.push(input);
            return {
              ok: true,
              json: {
                items: [
                  { id: 'job-b', description: '技能 B' },
                  { id: 'unknown/skill', description: '忽略我' },
                  { id: 'job-a', description: '技能 A' },
                ],
              },
            };
          },
        };
      },
    });

    const result = await translator([
      {
        jobId: 'job-a',
        gatewayType: 'hermes',
        gatewayId: 'hermes',
        skillId: 'skill/a',
        locale: 'zh',
        fieldSet: 'metadata',
        sourceHash: 'sha256:a',
        source: { description: longDescription },
      },
      {
        jobId: 'job-b',
        gatewayType: 'hermes',
        gatewayId: 'hermes',
        skillId: 'skill/b',
        locale: 'zh',
        fieldSet: 'metadata',
        sourceHash: 'sha256:b',
        source: { description: 'Short description' },
      },
    ], 'zh');

    assert.equal(result.get('job-a').description, '技能 A');
    assert.equal(result.get('job-b').description, '技能 B');
    assert.equal(result.size, 2);
    assert.match(calls[0].prompt, /"id":"job-a"/);
    assert.match(calls[0].prompt, /"id":"job-b"/);
    assert.match(calls[0].prompt, /"description":"A{200}"/);
    assert.doesNotMatch(calls[0].prompt, /SHOULD_NOT_BE_SENT/);
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
              return {
                ok: true,
                json: {
                  items: [
                    { id: 'tr_2', description: '中文描述' },
                  ],
                },
              };
            },
          };
        },
      });

      const result = await translator([
        {
          jobId: 'tr_2',
          gatewayType: 'hermes',
          gatewayId: 'Hermes',
          skillId: 'general/example',
          locale: 'zh',
          fieldSet: 'metadata',
          sourceHash: 'sha256:b',
          source: { description: 'English description' },
        },
      ], 'zh');

      assert.deepEqual(result, new Map([['tr_2', { description: '中文描述' }]]));
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
      () => translator([
        {
          jobId: 'tr_3',
          gatewayType: 'nanobot',
          gatewayId: 'nanobot',
          skillId: 'general/example',
          locale: 'zh',
          fieldSet: 'metadata',
          sourceHash: 'sha256:c',
          source: { description: 'English description' },
        },
      ], 'zh'),
      /description/,
    );
  });
});
