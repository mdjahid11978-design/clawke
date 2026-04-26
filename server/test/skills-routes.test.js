const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const {
  initSkillsRoutes,
  listSkillScopes,
  listSkills,
  getSkill,
  createSkill,
  updateSkill,
  setSkillEnabled,
  deleteSkill,
} = require('../dist/routes/skills-routes');

function res() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
}

function req({ query = {}, params = {}, body = {} } = {}) {
  return { query, params, body };
}

describe('Skills routes gateway-scoped RPC', () => {
  const calls = [];

  beforeEach(() => {
    calls.length = 0;
    initSkillsRoutes({
      getConnectedAccountIds: () => ['hermes-work', 'openclaw-local'],
      sendSkillRequest: async (payload) => {
        calls.push(payload);
        const request_id = payload.request_id || 'test-req';
        if (payload.type === 'skill_list') {
          return { type: 'skill_list_response', request_id, ok: true, skills: [{ id: 'apple/apple-notes' }] };
        }
        if (payload.type === 'skill_get') {
          return { type: 'skill_get_response', request_id, ok: true, skill: { id: payload.skill_id, body: 'body' } };
        }
        return { type: 'skill_mutation_response', request_id, ok: true, skill: { id: payload.skill_id || 'apple/apple-notes' }, deleted: payload.type === 'skill_delete' };
      },
    });
  });

  it('lists only gateway scopes, no library or all gateways', async () => {
    const response = res();

    await listSkillScopes(req(), response);

    assert.equal(response.statusCode, 200);
    assert.deepEqual(response.body.scopes.map((scope) => scope.id), [
      'gateway:hermes-work',
      'gateway:openclaw-local',
    ]);
    assert.equal(response.body.scopes.some((scope) => scope.id === 'library' || scope.id === 'all'), false);
  });

  it('forwards list/get/create/update/delete/enable to the selected gateway', async () => {
    await listSkills(req({ query: { gateway_id: 'hermes-work' } }), res());
    await getSkill(req({ query: { gateway_id: 'hermes-work' }, params: { category: 'apple', name: 'apple-notes' } }), res());
    await createSkill(req({ query: { gateway_id: 'hermes-work' }, body: { name: 'apple-notes', category: 'apple', description: 'Notes', body: 'Body' } }), res());
    await updateSkill(req({ query: { gateway_id: 'hermes-work' }, params: { category: 'apple', name: 'apple-notes' }, body: { name: 'apple-notes', category: 'apple', description: 'Notes 2', body: 'Body 2' } }), res());
    await setSkillEnabled(req({ query: { gateway_id: 'hermes-work' }, params: { category: 'apple', name: 'apple-notes' }, body: { enabled: false } }), res());
    await deleteSkill(req({ query: { gateway_id: 'hermes-work' }, params: { category: 'apple', name: 'apple-notes' } }), res());

    assert.deepEqual(calls.map((call) => call.type), [
      'skill_list',
      'skill_get',
      'skill_create',
      'skill_update',
      'skill_set_enabled',
      'skill_delete',
    ]);
    assert.ok(calls.every((call) => call.account_id === 'hermes-work'));
  });

  it('adds ready localization to skill list and detail responses', async () => {
    const localizationCalls = [];
    initSkillsRoutes({
      getConnectedAccountIds: () => ['hermes-work'],
      translationService: {
        getOrQueue(input) {
          localizationCalls.push(input);
          return {
            locale: input.locale,
            status: 'ready',
            name: '网页搜索',
            description: '搜索网页',
            trigger: input.fieldSet === 'detail' ? '需要联网搜索时使用' : undefined,
            body: input.fieldSet === 'detail' ? '## 翻译正文\n' : undefined,
          };
        },
      },
      sendSkillRequest: async (payload) => {
        const request_id = payload.request_id || 'test-req';
        if (payload.type === 'skill_list') {
          return {
            type: 'skill_list_response',
            request_id,
            ok: true,
            skills: [{
              id: 'general/web-search',
              name: 'web-search',
              description: 'Search the web',
              category: 'general',
              enabled: true,
              source: 'managed',
              sourceLabel: 'Managed',
              writable: true,
              deletable: true,
              path: 'general/web-search/SKILL.md',
              root: '/tmp/skills',
              updatedAt: 0,
              hasConflict: false,
            }],
          };
        }
        return {
          type: 'skill_get_response',
          request_id,
          ok: true,
          skill: {
            id: payload.skill_id,
            name: 'web-search',
            description: 'Search the web',
            category: 'general',
            trigger: 'Use when web lookup is needed',
            body: '## Source body\n',
            enabled: true,
            source: 'managed',
            sourceLabel: 'Managed',
            writable: true,
            deletable: true,
            path: 'general/web-search/SKILL.md',
            root: '/tmp/skills',
            updatedAt: 0,
            hasConflict: false,
          },
        };
      },
    });

    const listResponse = res();
    await listSkills(req({ query: { gateway_id: 'hermes-work', locale: 'zh-CN' } }), listResponse);

    assert.equal(listResponse.statusCode, 200);
    assert.equal(listResponse.body.skills[0].localization.locale, 'zh-CN');
    assert.equal(listResponse.body.skills[0].localization.status, 'ready');
    assert.equal(listResponse.body.skills[0].localization.name, undefined);
    assert.equal(listResponse.body.skills[0].localization.description, '搜索网页');
    assert.equal(listResponse.body.skills[0].sourceHash.length, 64);
    assert.equal(localizationCalls[0].fieldSet, 'metadata');
    assert.deepEqual(localizationCalls[0].source, {
      description: 'Search the web',
    });

    const detailResponse = res();
    await getSkill(req({
      query: { gateway_id: 'hermes-work', locale: 'zh-CN' },
      params: { category: 'general', name: 'web-search' },
    }), detailResponse);

    assert.equal(detailResponse.body.skill.localization.description, '搜索网页');
    assert.equal(detailResponse.body.skill.localization.trigger, undefined);
    assert.equal(detailResponse.body.skill.localization.body, undefined);
    assert.equal(localizationCalls[1].fieldSet, 'detail');
    assert.deepEqual(localizationCalls[1].source, {
      description: 'Search the web',
    });
  });
});
