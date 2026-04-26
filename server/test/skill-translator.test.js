import test from 'node:test';
import assert from 'node:assert/strict';
import { createConfiguredSkillTranslator } from '../dist/services/skill-translator.js';

test('configured skill translator calls OpenAI and returns only translated description', async () => {
  const calls = [];
  const translator = createConfiguredSkillTranslator({
    OPENAI_API_KEY: 'test-key',
    CLAWKE_TRANSLATION_MODEL: 'test-model',
  }, async (url, init) => {
    calls.push({ url: String(url), init });
    return {
      ok: true,
      status: 200,
      async json() {
        return {
          choices: [{
            message: {
              content: JSON.stringify({
                name: '网页搜索',
                description: '搜索网页',
              }),
            },
          }],
        };
      },
      async text() {
        return '';
      },
    };
  });

  const result = await translator({
    name: 'web-search',
    description: 'Search the web',
  }, 'zh-CN');

  assert.deepEqual(result, { description: '搜索网页' });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://api.openai.com/v1/chat/completions');
  const body = JSON.parse(calls[0].init.body);
  assert.equal(body.model, 'test-model');
  assert.match(body.messages[0].content, /target locale/);
  assert.match(body.messages[0].content, /already written/);
  assert.match(body.messages[1].content, /Search the web/);
  assert.doesNotMatch(body.messages[1].content, /web-search/);
});
