import test from 'node:test';
import assert from 'node:assert/strict';
import { Database } from '../dist/store/database.js';
import { SkillTranslationStore } from '../dist/store/skill-translation-store.js';
import { SkillTranslationService, startSkillTranslationWorker } from '../dist/services/skill-translation-service.js';

test('service returns ready cache and does not enqueue duplicate job', () => {
  const db = new Database(':memory:');
  const store = new SkillTranslationStore(db);
  const service = new SkillTranslationService({
    store,
    translator: async () => {
      throw new Error('translator should not be called');
    },
  });

  store.upsertCache({
    gateway_type: 'hermes',
    gateway_id: 'hermes',
    skill_id: 'general/web-search',
    locale: 'zh-CN',
    field_set: 'metadata',
    source_hash: 'sha256:a',
    translated_name: '网页搜索',
    translated_description: '搜索网页',
    status: 'ready',
  });

  const result = service.getOrQueue({
    gatewayType: 'hermes',
    gatewayId: 'hermes',
    skillId: 'general/web-search',
    locale: 'zh-CN',
    fieldSet: 'metadata',
    sourceHash: 'sha256:a',
    source: { name: 'web-search', description: 'Search' },
  });

  assert.equal(result.status, 'ready');
  assert.equal(result.name, undefined);
  assert.equal(result.description, '搜索网页');
  db.close();
});

test('service keeps Chinese source text for Chinese locale even if stale cache exists', () => {
  const db = new Database(':memory:');
  const store = new SkillTranslationStore(db);
  const service = new SkillTranslationService({
    store,
    translator: async () => {
      throw new Error('translator should not be called');
    },
  });
  const source = {
    description: '审查代码更改中的错误（bugs）、代码风格问题和最佳实践。',
  };

  store.upsertCache({
    gateway_type: 'OpenClaw',
    gateway_id: 'OpenClaw',
    skill_id: 'general/code-review',
    locale: 'zh',
    field_set: 'metadata',
    source_hash: 'sha256:stale',
    translated_name: null,
    translated_description: 'Review errors in code changes.',
    status: 'ready',
  });

  const result = service.getOrQueue({
    gatewayType: 'OpenClaw',
    gatewayId: 'OpenClaw',
    skillId: 'general/code-review',
    locale: 'zh',
    fieldSet: 'metadata',
    sourceHash: 'sha256:stale',
    source,
  });

  assert.equal(result.status, 'ready');
  assert.equal(result.description, source.description);
  assert.equal(store.nextPendingJob(), null);
  db.close();
});

test('service queues missing translation and worker stores ready cache without translating name', async () => {
  const db = new Database(':memory:');
  const store = new SkillTranslationStore(db);
  const calls = [];
  const service = new SkillTranslationService({
    store,
    translator: async (source, locale, context) => {
      calls.push({ source, locale, context });
      return {
      name: '网页搜索',
      description: '搜索网页',
      };
    },
  });

  const pending = service.getOrQueue({
    gatewayType: 'hermes',
    gatewayId: 'hermes',
    skillId: 'general/web-search',
    locale: 'zh-CN',
    fieldSet: 'metadata',
    sourceHash: 'sha256:a',
    source: { name: 'web-search', description: 'Search' },
  });
  assert.equal(pending.status, 'pending');

  assert.equal(await service.runNextJob(), true);
  const ready = service.getOrQueue({
    gatewayType: 'hermes',
    gatewayId: 'hermes',
    skillId: 'general/web-search',
    locale: 'zh-CN',
    fieldSet: 'metadata',
    sourceHash: 'sha256:a',
    source: { name: 'web-search', description: 'Search' },
  });

  assert.equal(ready.status, 'ready');
  assert.equal(ready.name, undefined);
  assert.equal(ready.description, '搜索网页');
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].source, { name: 'web-search', description: 'Search' });
  assert.equal(calls[0].locale, 'zh-CN');
  assert.equal(calls[0].context.gatewayType, 'hermes');
  assert.equal(calls[0].context.gatewayId, 'hermes');
  assert.equal(calls[0].context.skillId, 'general/web-search');
  assert.equal(calls[0].context.locale, 'zh-CN');
  assert.equal(calls[0].context.fieldSet, 'metadata');
  assert.equal(calls[0].context.sourceHash, 'sha256:a');
  assert.equal(typeof calls[0].context.jobId, 'string');
  db.close();
});

test('service marks translation job failed when translator rejects', async () => {
  const db = new Database(':memory:');
  const store = new SkillTranslationStore(db);
  const service = new SkillTranslationService({
    store,
    translator: async () => {
      throw new Error('Skill translation response did not include description.');
    },
  });

  service.getOrQueue({
    gatewayType: 'openclaw',
    gatewayId: 'OpenClaw',
    skillId: 'openclaw-bundled/1password',
    locale: 'zh',
    fieldSet: 'metadata',
    sourceHash: 'sha256:failed',
    source: { description: 'Set up and use 1Password CLI.' },
  });

  assert.equal(await service.runNextJob(), false);
  const row = db.raw.prepare(`
    SELECT status, last_error
    FROM skill_translation_jobs
    WHERE gateway_id = ? AND skill_id = ? AND source_hash = ?
  `).get('OpenClaw', 'openclaw-bundled/1password', 'sha256:failed');

  assert.equal(row.status, 'failed');
  assert.match(row.last_error, /description/);
  db.close();
});

test('translation worker drains pending jobs in the background', async () => {
  const db = new Database(':memory:');
  const store = new SkillTranslationStore(db);
  const service = new SkillTranslationService({
    store,
    translator: async () => ({
      description: '搜索网页',
    }),
  });

  service.getOrQueue({
    gatewayType: 'hermes',
    gatewayId: 'hermes',
    skillId: 'general/web-search',
    locale: 'zh-CN',
    fieldSet: 'metadata',
    sourceHash: 'sha256:a',
    source: { description: 'Search' },
  });

  const stop = startSkillTranslationWorker(service, { intervalMs: 5 });
  try {
    await waitFor(async () => {
      const ready = service.getOrQueue({
        gatewayType: 'hermes',
        gatewayId: 'hermes',
        skillId: 'general/web-search',
        locale: 'zh-CN',
        fieldSet: 'metadata',
        sourceHash: 'sha256:a',
        source: { description: 'Search' },
      });
      return ready.status === 'ready' && ready.description === '搜索网页';
    });
  } finally {
    stop();
    db.close();
  }
});

async function waitFor(predicate, timeoutMs = 500) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.fail('condition was not met before timeout');
}
