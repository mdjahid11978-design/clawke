#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const BASE_URL = process.env.CLAWKE_E2E_HTTP_URL || 'http://127.0.0.1:8780';
const REQUEST_TIMEOUT_MS = Number(process.env.CLAWKE_E2E_TIMEOUT_MS || 10000);
const CATEGORY = process.env.CLAWKE_E2E_SKILL_CATEGORY || 'e2e';
const NAME = process.env.CLAWKE_E2E_SKILL_NAME || `clawke-e2e-skill-${Date.now()}`;
const SKILL_ID = `${CATEGORY}/${NAME}`;

let token = '';
try {
  const cfg = JSON.parse(
    readFileSync(join(homedir(), '.clawke', 'clawke.json'), 'utf-8'),
  );
  token = cfg.relay?.token || '';
} catch {}

const testCases = [
  {
    id: 'SKILL-E2E-001',
    doc: 'PRD 9.3',
    name: '创建新技能生成标准 SKILL.md',
    run: createSkill,
  },
  {
    id: 'SKILL-E2E-002',
    doc: 'PRD 9.4',
    name: '编辑已有 managed 技能并保存',
    run: editSkill,
  },
  {
    id: 'SKILL-E2E-003',
    doc: 'PRD 9.5',
    name: '禁用技能后列表状态保持为 disabled',
    run: disableSkill,
  },
  {
    id: 'SKILL-E2E-004',
    doc: 'PRD 9.5',
    name: '启用技能后列表状态恢复为 enabled',
    run: enableSkill,
  },
  {
    id: 'SKILL-E2E-005',
    doc: 'PRD 9.6',
    name: '删除 managed 技能后列表同步移除',
    run: deleteSkill,
  },
];

let gatewayId = process.env.CLAWKE_E2E_GATEWAY_ID || '';

async function main() {
  console.log('Clawke Skills Management E2E');
  console.log(`Base URL: ${BASE_URL}`);
  console.log(`Skill ID: ${SKILL_ID}`);

  gatewayId = gatewayId || await resolveGatewayId();
  console.log(`Gateway: ${gatewayId}\n`);

  await cleanupIfExists();

  const passed = [];
  try {
    for (const testCase of testCases) {
      await runCase(testCase);
      passed.push(testCase.id);
    }
  } finally {
    if (!passed.includes('SKILL-E2E-005')) {
      await cleanupIfExists();
    }
  }

  console.log('\nPASS: skills management lifecycle e2e');
}

async function runCase(testCase) {
  process.stdout.write(`${testCase.id} ${testCase.doc} ${testCase.name} ... `);
  await testCase.run();
  console.log('PASS');
}

async function createSkill() {
  const response = await request('/api/skills', {
    method: 'POST',
    query: { gateway_id: gatewayId, locale: 'zh' },
    body: {
      name: NAME,
      category: CATEGORY,
      description: 'Created by Clawke skills management E2E',
      trigger: 'Use when validating Clawke skills management E2E',
      body: [
        `# ${NAME}`,
        '',
        '## Purpose',
        '',
        'Validate Clawke skill creation from the management page lifecycle.',
      ].join('\n'),
    },
  });

  assert.equal(response.status, 201, response.text);
  assert.equal(response.json.skill.id, SKILL_ID);
  assert.equal(response.json.skill.name, NAME);
  assert.equal(response.json.skill.category, CATEGORY);
  assert.equal(response.json.skill.enabled, true);
  assert.equal(response.json.skill.source, 'managed');
  assert.equal(response.json.skill.writable, true);
  assert.equal(response.json.skill.deletable, true);

  const detail = await getSkill();
  assert.equal(detail.skill.id, SKILL_ID);
  assert.match(detail.skill.body || detail.skill.content || '', /Purpose/);
}

async function editSkill() {
  const response = await request(skillPath(), {
    method: 'PUT',
    query: { gateway_id: gatewayId, locale: 'zh' },
    body: {
      name: NAME,
      category: CATEGORY,
      description: 'Edited by Clawke skills management E2E',
      trigger: 'Use after editing Clawke skills management E2E',
      body: [
        `# ${NAME}`,
        '',
        '## Purpose',
        '',
        'Validate Clawke skill editing from the management page lifecycle.',
        '',
        '## Workflow',
        '',
        '1. Create a skill.',
        '2. Edit the skill.',
      ].join('\n'),
    },
  });

  assert.equal(response.status, 200, response.text);
  assert.equal(response.json.skill.id, SKILL_ID);
  assert.equal(
    response.json.skill.description,
    'Edited by Clawke skills management E2E',
  );

  const detail = await getSkill();
  assert.equal(
    detail.skill.description,
    'Edited by Clawke skills management E2E',
  );
  assert.match(detail.skill.body || detail.skill.content || '', /Workflow/);
}

async function disableSkill() {
  const response = await request(`${skillPath()}/enabled`, {
    method: 'PUT',
    query: { gateway_id: gatewayId },
    body: { enabled: false },
  });

  assert.equal(response.status, 200, response.text);
  assert.equal(response.json.ok, true);
  if (response.json.skill) {
    assert.equal(response.json.skill.enabled, false);
  }

  const skill = await findSkill();
  assert.equal(skill.enabled, false);
}

async function enableSkill() {
  const response = await request(`${skillPath()}/enabled`, {
    method: 'PUT',
    query: { gateway_id: gatewayId },
    body: { enabled: true },
  });

  assert.equal(response.status, 200, response.text);
  assert.equal(response.json.ok, true);
  if (response.json.skill) {
    assert.equal(response.json.skill.enabled, true);
  }

  const skill = await findSkill();
  assert.equal(skill.enabled, true);
}

async function deleteSkill() {
  const response = await request(skillPath(), {
    method: 'DELETE',
    query: { gateway_id: gatewayId },
  });

  assert.equal(response.status, 200, response.text);
  assert.equal(response.json.ok, true);

  const skills = await listSkills();
  assert.equal(skills.some((skill) => skill.id === SKILL_ID), false);
}

async function resolveGatewayId() {
  const response = await request('/api/gateways');
  assert.equal(response.status, 200, response.text);
  const gateways = response.json.gateways || [];
  const gateway = gateways.find(
    (item) =>
      item.status === 'online' &&
      Array.isArray(item.capabilities) &&
      item.capabilities.includes('skills'),
  );
  assert.ok(
    gateway,
    'No online gateway with skills capability. Set CLAWKE_E2E_GATEWAY_ID to run against a specific gateway.',
  );
  return gateway.gateway_id;
}

async function listSkills() {
  const response = await request('/api/skills', {
    query: { gateway_id: gatewayId, locale: 'zh' },
  });
  assert.equal(response.status, 200, response.text);
  return response.json.skills || [];
}

async function findSkill() {
  const skills = await listSkills();
  const skill = skills.find((item) => item.id === SKILL_ID);
  assert.ok(skill, `Skill not found in list: ${SKILL_ID}`);
  return skill;
}

async function getSkill() {
  const response = await request(skillPath(), {
    query: { gateway_id: gatewayId, locale: 'zh' },
  });
  assert.equal(response.status, 200, response.text);
  return response.json;
}

async function cleanupIfExists() {
  try {
    const skills = await listSkills();
    if (!skills.some((skill) => skill.id === SKILL_ID)) return;
    await request(`${skillPath()}/enabled`, {
      method: 'PUT',
      query: { gateway_id: gatewayId },
      body: { enabled: true },
    });
    await request(skillPath(), {
      method: 'DELETE',
      query: { gateway_id: gatewayId },
    });
  } catch (err) {
    console.warn(`Cleanup warning: ${err instanceof Error ? err.message : err}`);
  }
}

function skillPath() {
  return `/api/skills/${encodeURIComponent(CATEGORY)}/${encodeURIComponent(NAME)}`;
}

async function request(path, { method = 'GET', query, body } = {}) {
  const url = new URL(path, BASE_URL);
  for (const [key, value] of Object.entries(query || {})) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method,
      signal: controller.signal,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {}
    return { status: response.status, json, text };
  } finally {
    clearTimeout(timeout);
  }
}

main().catch((err) => {
  console.error('\nFAIL:', err instanceof Error ? err.message : err);
  process.exit(1);
});
