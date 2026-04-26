import test from 'node:test';
import assert from 'node:assert/strict';
import { Database } from '../dist/store/database.js';
import { SkillTranslationStore } from '../dist/store/skill-translation-store.js';

test('translation store deduplicates cache by source hash and locale', () => {
  const db = new Database(':memory:');
  const store = new SkillTranslationStore(db);

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

  const item = store.getReadyCache({
    gateway_type: 'hermes',
    gateway_id: 'hermes',
    skill_id: 'general/web-search',
    locale: 'zh-CN',
    field_set: 'metadata',
    source_hash: 'sha256:a',
  });

  assert.equal(item.translated_name, '网页搜索');
  assert.equal(item.translated_description, '搜索网页');
  db.close();
});

test('translation store returns existing queued job for same key', () => {
  const db = new Database(':memory:');
  const store = new SkillTranslationStore(db);
  const key = {
    gateway_type: 'hermes',
    gateway_id: 'hermes',
    skill_id: 'general/web-search',
    locale: 'zh-CN',
    field_set: 'metadata',
    source_hash: 'sha256:a',
  };

  const first = store.enqueueJob(key);
  const second = store.enqueueJob(key);

  assert.equal(second, first);
  db.close();
});
