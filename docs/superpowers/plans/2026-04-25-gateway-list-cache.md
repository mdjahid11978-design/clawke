# Gateway List Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建统一 Gateway 列表能力：Server 区分“已配置但未连接”和“已连接”，Client 用 DB 缓存 Gateway 元信息，任务管理页和技能中心复用同一个 Gateway 选择组件，并支持右键 Server-first 重命名。

**Architecture:** Server 提供 `/api/gateways` 作为 Gateway 当前有效清单，来源是本机配置清单加当前 upstream WebSocket 连接；Server 不返回的 Gateway 视为不存在，Client 同步时删除本地缓存。Flutter Client 用 Drift 缓存 Gateway 元信息，通过 Repository watch DB 立即渲染，再异步拉 Server 刷新；任务管理和技能中心只消费统一的 `GatewaySelectorPane`。

**Tech Stack:** Node.js/Express + better-sqlite3 + node:test；Flutter + Riverpod + Drift + Dio；OpenClaw TypeScript gateway；Hermes Python gateway。

---

## 核心规则

- Server 返回 = 当前仍然存在的 Gateway。
- Server 不返回 = Gateway 已从配置删除且当前未连接，Client 删除本地缓存。
- 不建模 `missing` 状态。
- 状态只表达存在后的连接情况：`online`、`disconnected`、`error`。
- 任务管理页和技能中心只显示 `status = online` 且 capability 匹配的 Gateway。
- 重命名必须 Server-first：先 `PATCH /api/gateways/:gateway_id`，成功后再同步 DB，不做本地优先生效。
- Gateway 右键重命名行为对齐会话列表右键重命名。

## Server 返回语义

`GET /api/gateways` 返回配置中存在的 Gateway，以及当前已连接但不在配置中的 Gateway。

示例：

```json
{
  "gateways": [
    {
      "gateway_id": "hermes",
      "display_name": "Hermes",
      "gateway_type": "hermes",
      "status": "disconnected",
      "capabilities": ["chat", "tasks", "skills", "models"],
      "last_connected_at": 1710000000000,
      "last_seen_at": 1710000000000
    },
    {
      "gateway_id": "OpenClaw",
      "display_name": "OpenClaw",
      "gateway_type": "openclaw",
      "status": "online",
      "capabilities": ["chat", "tasks", "skills", "models"],
      "last_connected_at": 1710000000000,
      "last_seen_at": 1710000000000
    }
  ]
}
```

同步规则：

```text
configuredIds = ~/.clawke/clawke.json 中的 gateways.*[].id
onlineIds = upstreamConnections 中 readyState=OPEN 的 account_id
serverIds = configuredIds ∪ onlineIds

对 serverIds:
  返回 gateway，status = online / disconnected / error

对 Server metadata DB 里有但 serverIds 没有的:
  不返回

对 Client DB 里有但 GET /api/gateways 没返回的:
  删除本地缓存
```

---

## 文件结构

### Server

- Create: `server/src/types/gateways.ts`
  - 定义 `GatewayInfo`、`GatewayStatus`、`GatewayMetadataPatch`。
- Create: `server/src/store/gateway-store.ts`
  - 持久化用户重命名、capabilities、last seen/error 等 Server 侧元信息。
- Create: `server/src/services/gateway-config-service.ts`
  - 读取 `~/.clawke/clawke.json`，产出配置中存在的 Gateway 清单。
- Create: `server/src/routes/gateway-routes.ts`
  - 实现 `GET /api/gateways` 和 `PATCH /api/gateways/:gatewayId`。
- Modify: `server/src/store/database.ts`
  - 增加 `gateway_metadata` 表。
- Modify: `server/src/upstream/openclaw-listener.ts`
  - 保存 connected gateway 的详细 metadata，而不只是 account id。
  - `identify` 支持 `agentName`、`gatewayType`、`capabilities`。
- Modify: `server/src/http-server.ts`
  - 注册 `/api/gateways` routes，root endpoint 列表加入 `/api/gateways`。
- Modify: `server/src/index.ts`
  - 初始化 gateway routes 依赖，连接/断开时更新 GatewayStore。
- Test: `server/test/gateway-store.test.js`
- Test: `server/test/gateway-routes.test.js`

### Gateway

- Modify: `gateways/openclaw/clawke/src/gateway.ts`
  - `identify` 消息增加 `agentName: "OpenClaw"`、`gatewayType: "openclaw"`、capabilities。
- Modify: `gateways/hermes/clawke/clawke_channel.py`
  - `identify` 消息增加 `agentName: "Hermes"`、`gatewayType: "hermes"`、capabilities。

### Flutter Client

- Create: `client/lib/data/database/tables/gateways.drift`
  - Drift Gateway 缓存表。
- Modify: `client/lib/data/database/app_database.dart`
  - include `gateways.drift`，schemaVersion +1，migration 增加表。
- Create: `client/lib/data/database/dao/gateway_dao.dart`
  - watch/upsert/delete/rename cache 操作。
- Create: `client/lib/models/gateway_info.dart`
  - Client Gateway domain model。
- Create: `client/lib/services/gateways_api_service.dart`
  - Dio API client：`GET /api/gateways`、`PATCH /api/gateways/:id`。
- Create: `client/lib/data/repositories/gateway_repository.dart`
  - DB-first watch、Server sync、Server-first rename。
- Modify: `client/lib/providers/database_providers.dart`
  - 注册 `GatewayDao` 和 `GatewayRepository`。
- Create: `client/lib/providers/gateway_provider.dart`
  - `gatewayListProvider`、`onlineGatewayListProvider`、`selectedGatewayProvider`。
- Modify: `client/lib/providers/chat_provider.dart`
  - 收到 `ai_connected` / `ai_disconnected` 时更新 GatewayRepository，并触发 sync。
- Create: `client/lib/widgets/gateway_selector_pane.dart`
  - 桌面 sidebar + 移动 bottom sheet 的统一 Gateway 选择组件。
- Modify: `client/lib/screens/tasks_management_screen.dart`
  - 删除内置 `_GatewaySidebar` / `_GatewayTile` / `_MobileGatewaySelector`，改用 `GatewaySelectorPane`。
- Modify: `client/lib/providers/tasks_provider.dart`
  - 接收统一 Gateway model 或 gatewayId，不再自维护 `TaskAccount` 列表来源。
- Modify: `client/lib/screens/skills_management_screen.dart`
  - 删除内置 `_ScopeSidebar` / `_ScopeTile` / `_MobileScopeSelector`，改用 `GatewaySelectorPane`。
- Modify: `client/lib/providers/skills_provider.dart`
  - Gateway 列表来源改为 `GatewayRepository`；技能 API 调用仍使用 `gateway_id`。
- Test: `client/test/data/database/gateway_dao_test.dart`
- Test: `client/test/providers/gateway_repository_test.dart`
- Test: `client/test/widgets/gateway_selector_pane_test.dart`
- Test: 更新 `client/test/tasks_management_screen_test.dart`
- Test: 更新 `client/test/skills_management_screen_test.dart`

---

## Task 1: Server Gateway Store and Config Source

**Files:**
- Create: `server/src/types/gateways.ts`
- Create: `server/src/store/gateway-store.ts`
- Create: `server/src/services/gateway-config-service.ts`
- Modify: `server/src/store/database.ts`
- Test: `server/test/gateway-store.test.js`

- [x] **Step 1: 写 failing test**

创建 `server/test/gateway-store.test.js`：

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { Database } from '../dist/store/database.js';
import { GatewayStore } from '../dist/store/gateway-store.js';

test('gateway store persists display name and online metadata', () => {
  const db = new Database(':memory:');
  const store = new GatewayStore(db);

  store.upsertRuntime({
    gateway_id: 'hermes',
    display_name: 'Hermes',
    gateway_type: 'hermes',
    status: 'online',
    capabilities: ['chat', 'tasks', 'skills', 'models'],
    last_connected_at: 100,
    last_seen_at: 100,
  });
  store.rename('hermes', 'Personal Hermes');

  const item = store.get('hermes');
  assert.equal(item.display_name, 'Personal Hermes');
  assert.equal(item.gateway_type, 'hermes');
  assert.equal(item.status, 'online');
  assert.deepEqual(item.capabilities, ['chat', 'tasks', 'skills', 'models']);
  db.close();
});

test('gateway store deletes rows absent from server snapshot', () => {
  const db = new Database(':memory:');
  const store = new GatewayStore(db);

  store.upsertRuntime({
    gateway_id: 'old',
    display_name: 'Old Gateway',
    gateway_type: 'hermes',
    status: 'disconnected',
    capabilities: ['chat'],
    last_connected_at: null,
    last_seen_at: null,
  });
  store.deleteMissing(['hermes']);

  assert.equal(store.get('old'), null);
  db.close();
});
```

- [x] **Step 2: 运行测试，确认失败**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/gateway-store.test.js
```

Expected: FAIL，因为 `gateway-store.js` 不存在。

- [x] **Step 3: 定义 Server Gateway 类型**

创建 `server/src/types/gateways.ts`：

```ts
export type GatewayStatus = 'online' | 'disconnected' | 'error';

export interface GatewayInfo {
  gateway_id: string;
  display_name: string;
  gateway_type: string;
  status: GatewayStatus;
  capabilities: string[];
  last_error_code?: string | null;
  last_error_message?: string | null;
  last_connected_at?: number | null;
  last_seen_at?: number | null;
}

export interface GatewayMetadataPatch {
  display_name?: string;
}

export interface ConfiguredGateway {
  gateway_id: string;
  gateway_type: string;
  display_name: string;
  capabilities: string[];
}
```

- [x] **Step 4: 增加 Server DB 表**

修改 `server/src/store/database.ts`，在 `CREATE TABLE IF NOT EXISTS metadata` 后追加：

```ts
        CREATE TABLE IF NOT EXISTS gateway_metadata (
          gateway_id TEXT PRIMARY KEY,
          display_name TEXT,
          gateway_type TEXT,
          status TEXT NOT NULL DEFAULT 'disconnected',
          capabilities_json TEXT NOT NULL DEFAULT '[]',
          last_error_code TEXT,
          last_error_message TEXT,
          last_connected_at INTEGER,
          last_seen_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
```

在 migration 末尾追加幂等创建：

```ts
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS gateway_metadata (
        gateway_id TEXT PRIMARY KEY,
        display_name TEXT,
        gateway_type TEXT,
        status TEXT NOT NULL DEFAULT 'disconnected',
        capabilities_json TEXT NOT NULL DEFAULT '[]',
        last_error_code TEXT,
        last_error_message TEXT,
        last_connected_at INTEGER,
        last_seen_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    `);
```

- [x] **Step 5: 实现 GatewayStore**

创建 `server/src/store/gateway-store.ts`：

```ts
import type BetterSqlite3 from 'better-sqlite3';
import type { Database } from './database.js';
import type { GatewayInfo } from '../types/gateways.js';

type GatewayRow = {
  gateway_id: string;
  display_name: string | null;
  gateway_type: string | null;
  status: string;
  capabilities_json: string;
  last_error_code: string | null;
  last_error_message: string | null;
  last_connected_at: number | null;
  last_seen_at: number | null;
};

export class GatewayStore {
  private db: BetterSqlite3.Database;

  constructor(database: Database) {
    this.db = database.raw;
  }

  get(gatewayId: string): GatewayInfo | null {
    const row = this.db.prepare('SELECT * FROM gateway_metadata WHERE gateway_id = ?').get(gatewayId) as GatewayRow | undefined;
    return row ? this.toInfo(row) : null;
  }

  list(): GatewayInfo[] {
    const rows = this.db.prepare('SELECT * FROM gateway_metadata ORDER BY display_name COLLATE NOCASE, gateway_id').all() as GatewayRow[];
    return rows.map((row) => this.toInfo(row));
  }

  upsertRuntime(info: GatewayInfo): void {
    const existing = this.get(info.gateway_id);
    const displayName = existing?.display_name || info.display_name || info.gateway_id;
    const now = Date.now();
    this.db.prepare(`
      INSERT INTO gateway_metadata (
        gateway_id, display_name, gateway_type, status, capabilities_json,
        last_error_code, last_error_message, last_connected_at, last_seen_at,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(gateway_id) DO UPDATE SET
        display_name = excluded.display_name,
        gateway_type = excluded.gateway_type,
        status = excluded.status,
        capabilities_json = excluded.capabilities_json,
        last_error_code = excluded.last_error_code,
        last_error_message = excluded.last_error_message,
        last_connected_at = excluded.last_connected_at,
        last_seen_at = excluded.last_seen_at,
        updated_at = excluded.updated_at
    `).run(
      info.gateway_id,
      displayName,
      info.gateway_type,
      info.status,
      JSON.stringify(info.capabilities),
      info.last_error_code ?? null,
      info.last_error_message ?? null,
      info.last_connected_at ?? null,
      info.last_seen_at ?? null,
      now,
      now,
    );
  }

  rename(gatewayId: string, displayName: string): boolean {
    const now = Date.now();
    const result = this.db.prepare(`
      UPDATE gateway_metadata SET display_name = ?, updated_at = ? WHERE gateway_id = ?
    `).run(displayName, now, gatewayId);
    return result.changes > 0;
  }

  deleteMissing(serverIds: string[]): void {
    const ids = new Set(serverIds);
    for (const item of this.list()) {
      if (!ids.has(item.gateway_id)) {
        this.db.prepare('DELETE FROM gateway_metadata WHERE gateway_id = ?').run(item.gateway_id);
      }
    }
  }

  private toInfo(row: GatewayRow): GatewayInfo {
    let capabilities: string[] = [];
    try {
      capabilities = JSON.parse(row.capabilities_json);
    } catch {
      capabilities = [];
    }
    return {
      gateway_id: row.gateway_id,
      display_name: row.display_name || row.gateway_id,
      gateway_type: row.gateway_type || 'unknown',
      status: row.status === 'online' || row.status === 'error' ? row.status : 'disconnected',
      capabilities,
      last_error_code: row.last_error_code,
      last_error_message: row.last_error_message,
      last_connected_at: row.last_connected_at,
      last_seen_at: row.last_seen_at,
    };
  }
}
```

- [x] **Step 6: 实现配置来源**

创建 `server/src/services/gateway-config-service.ts`：

```ts
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { ConfiguredGateway } from '../types/gateways.js';

const DEFAULT_CAPABILITIES = ['chat', 'tasks', 'skills', 'models'];

export function listConfiguredGateways(configPath = path.join(os.homedir(), '.clawke', 'clawke.json')): ConfiguredGateway[] {
  if (!fs.existsSync(configPath)) return [];
  const raw = JSON.parse(fs.readFileSync(configPath, 'utf-8')) as Record<string, unknown>;
  const gateways = raw.gateways as Record<string, unknown> | undefined;
  if (!gateways) return [];

  const result: ConfiguredGateway[] = [];
  for (const [gatewayType, list] of Object.entries(gateways)) {
    if (!Array.isArray(list)) continue;
    for (const item of list as Array<Record<string, unknown>>) {
      const id = typeof item.id === 'string' && item.id.trim() ? item.id.trim() : '';
      if (!id) continue;
      result.push({
        gateway_id: id,
        gateway_type: gatewayType,
        display_name: displayNameFor(gatewayType, id),
        capabilities: DEFAULT_CAPABILITIES,
      });
    }
  }
  return result;
}

function displayNameFor(gatewayType: string, id: string): string {
  if (gatewayType === 'hermes') return 'Hermes';
  if (gatewayType === 'openclaw') return 'OpenClaw';
  if (gatewayType === 'nanobot') return 'nanobot';
  return id;
}
```

- [x] **Step 7: 运行测试**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/gateway-store.test.js
```

Expected: PASS.

---

## Task 2: Server Gateway Routes and Runtime Snapshot

**Files:**
- Create: `server/src/routes/gateway-routes.ts`
- Modify: `server/src/upstream/openclaw-listener.ts`
- Modify: `server/src/http-server.ts`
- Modify: `server/src/index.ts`
- Test: `server/test/gateway-routes.test.js`

- [x] **Step 1: 写 route failing test**

创建 `server/test/gateway-routes.test.js`，直接测试 route helpers，避免启动真实端口：

```js
import test from 'node:test';
import assert from 'node:assert/strict';

test('listGateways returns configured disconnected and online gateways', async () => {
  const mod = await import('../dist/routes/gateway-routes.js');
  const responses = [];
  mod.initGatewayRoutes({
    gatewayStore: {
      get: (id) => id === 'hermes' ? { gateway_id: 'hermes', display_name: 'Personal Hermes', gateway_type: 'hermes', status: 'disconnected', capabilities: ['chat', 'tasks'] } : null,
      upsertRuntime: () => {},
      rename: () => true,
      deleteMissing: () => {},
    },
    listConfiguredGateways: () => [{ gateway_id: 'hermes', display_name: 'Hermes', gateway_type: 'hermes', capabilities: ['chat', 'tasks'] }],
    getConnectedGateways: () => [{ gateway_id: 'OpenClaw', display_name: 'OpenClaw', gateway_type: 'openclaw', status: 'online', capabilities: ['chat', 'skills'] }],
  });

  await mod.listGateways({}, { json: (body) => responses.push(body) });
  assert.equal(responses[0].gateways.length, 2);
  assert.equal(responses[0].gateways[0].gateway_id, 'hermes');
  assert.equal(responses[0].gateways[0].display_name, 'Personal Hermes');
  assert.equal(responses[0].gateways[0].status, 'disconnected');
  assert.equal(responses[0].gateways[1].status, 'online');
});

test('renameGateway is server first and rejects empty names', async () => {
  const mod = await import('../dist/routes/gateway-routes.js');
  const statuses = [];
  const bodies = [];
  mod.initGatewayRoutes({
    gatewayStore: {
      get: () => ({ gateway_id: 'hermes', display_name: 'Hermes', gateway_type: 'hermes', status: 'online', capabilities: ['chat'] }),
      upsertRuntime: () => {},
      rename: () => true,
      deleteMissing: () => {},
    },
    listConfiguredGateways: () => [],
    getConnectedGateways: () => [],
  });

  await mod.renameGateway(
    { params: { gatewayId: 'hermes' }, body: { display_name: '' } },
    { status: (code) => { statuses.push(code); return { json: (body) => bodies.push(body) }; } },
  );
  assert.equal(statuses[0], 400);
});
```

- [x] **Step 2: 运行测试，确认失败**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/gateway-routes.test.js
```

Expected: FAIL，因为 `gateway-routes.js` 不存在。

- [x] **Step 3: 扩展 openclaw-listener runtime metadata**

修改 `server/src/upstream/openclaw-listener.ts`：

```ts
import type { GatewayInfo } from '../types/gateways.js';

const upstreamConnections = new Map<string, WebSocket>();
const upstreamGatewayInfo = new Map<string, GatewayInfo>();

export function getConnectedGateways(): GatewayInfo[] {
  const result: GatewayInfo[] = [];
  for (const [id, ws] of upstreamConnections) {
    if (ws.readyState !== 1) continue;
    const info = upstreamGatewayInfo.get(id);
    result.push(info || {
      gateway_id: id,
      display_name: id,
      gateway_type: 'unknown',
      status: 'online',
      capabilities: ['chat'],
      last_connected_at: null,
      last_seen_at: Date.now(),
    });
  }
  return result;
}
```

在 `payload.type === 'identify'` 分支里，把硬编码 `agent_name: 'OpenClaw'` 改为 payload 传入值：

```ts
const displayName = typeof payload.agentName === 'string' && payload.agentName.trim()
  ? payload.agentName.trim()
  : 'OpenClaw';
const gatewayType = typeof payload.gatewayType === 'string' && payload.gatewayType.trim()
  ? payload.gatewayType.trim()
  : 'openclaw';
const capabilities = Array.isArray(payload.capabilities)
  ? payload.capabilities.map((item) => String(item)).filter(Boolean)
  : ['chat', 'tasks', 'skills', 'models'];
const now = Date.now();

upstreamGatewayInfo.set(accountId!, {
  gateway_id: accountId!,
  display_name: displayName,
  gateway_type: gatewayType,
  status: 'online',
  capabilities,
  last_connected_at: now,
  last_seen_at: now,
});

if (onGatewayIdentified) {
  onGatewayIdentified(accountId!, displayName);
}

broadcastToClients({
  payload_type: 'system_status',
  status: 'ai_connected',
  agent_name: displayName,
  gateway_type: gatewayType,
  capabilities,
  account_id: accountId,
});
```

在 close 分支删除 runtime metadata：

```ts
upstreamGatewayInfo.delete(accountId);
```

- [x] **Step 4: 实现 gateway routes**

创建 `server/src/routes/gateway-routes.ts`：

```ts
import type { Request, Response } from 'express';
import type { ConfiguredGateway, GatewayInfo } from '../types/gateways.js';
import type { GatewayStore } from '../store/gateway-store.js';
import { listConfiguredGateways as defaultListConfiguredGateways } from '../services/gateway-config-service.js';

interface GatewayRoutesDeps {
  gatewayStore: Pick<GatewayStore, 'get' | 'upsertRuntime' | 'rename' | 'deleteMissing'>;
  listConfiguredGateways?: () => ConfiguredGateway[];
  getConnectedGateways: () => GatewayInfo[];
}

let deps: GatewayRoutesDeps | null = null;

export function initGatewayRoutes(nextDeps: GatewayRoutesDeps): void {
  deps = nextDeps;
}

export async function listGateways(_req: Request, res: Response): Promise<void> {
  const activeDeps = requireDeps();
  const configured = (activeDeps.listConfiguredGateways || defaultListConfiguredGateways)();
  const connected = activeDeps.getConnectedGateways();
  const connectedMap = new Map(connected.map((item) => [item.gateway_id, item]));
  const ids = new Set<string>();
  const result: GatewayInfo[] = [];

  for (const item of configured) {
    ids.add(item.gateway_id);
    const runtime = connectedMap.get(item.gateway_id);
    const stored = activeDeps.gatewayStore.get(item.gateway_id);
    const info: GatewayInfo = runtime || {
      gateway_id: item.gateway_id,
      display_name: stored?.display_name || item.display_name,
      gateway_type: item.gateway_type,
      status: 'disconnected',
      capabilities: stored?.capabilities?.length ? stored.capabilities : item.capabilities,
      last_connected_at: stored?.last_connected_at ?? null,
      last_seen_at: stored?.last_seen_at ?? null,
    };
    activeDeps.gatewayStore.upsertRuntime(info);
    result.push(info);
  }

  for (const item of connected) {
    if (ids.has(item.gateway_id)) continue;
    ids.add(item.gateway_id);
    activeDeps.gatewayStore.upsertRuntime(item);
    result.push(item);
  }

  activeDeps.gatewayStore.deleteMissing([...ids]);
  res.json({ gateways: result });
}

export async function renameGateway(req: Request, res: Response): Promise<void> {
  const activeDeps = requireDeps();
  const gatewayId = String(req.params.gatewayId || '').trim();
  const displayName = String(req.body?.display_name || '').trim();
  if (!gatewayId) {
    res.status(400).json({ error: 'validation_error', message: 'gateway_id is required.' });
    return;
  }
  if (!displayName) {
    res.status(400).json({ error: 'validation_error', message: 'display_name is required.' });
    return;
  }
  const existing = activeDeps.gatewayStore.get(gatewayId);
  if (!existing) {
    res.status(404).json({ error: 'gateway_not_found', message: `Gateway not found: ${gatewayId}` });
    return;
  }
  activeDeps.gatewayStore.rename(gatewayId, displayName);
  res.json({ ok: true, gateway: { ...existing, display_name: displayName } });
}

function requireDeps(): GatewayRoutesDeps {
  if (!deps) throw new Error('gateway routes not initialized');
  return deps;
}
```

- [x] **Step 5: 注册 HTTP routes**

修改 `server/src/http-server.ts`：

```ts
import { listGateways, renameGateway } from './routes/gateway-routes.js';
```

在 endpoint 列表加入：

```ts
'/api/gateways',
```

在 task routes 附近注册：

```ts
  app.get('/api/gateways', listGateways);
  app.patch('/api/gateways/:gatewayId', renameGateway);
```

- [x] **Step 6: 初始化 routes**

修改 `server/src/index.ts` openclaw mode import：

```ts
const { startOpenClawListener, sendToOpenClaw, isUpstreamConnected, getConnectedAccountIds, getConnectedGateways, queryGatewayModels, queryGatewaySkills } =
  await import('./upstream/openclaw-listener.js');
const { initGatewayRoutes } = await import('./routes/gateway-routes.js');
const { GatewayStore } = await import('./store/gateway-store.js');
```

在 DB store 初始化后创建：

```ts
const gatewayStore = new GatewayStore(db);
```

在 openclaw mode routes 初始化处加入：

```ts
initGatewayRoutes({
  gatewayStore,
  getConnectedGateways,
});
```

- [x] **Step 7: 运行 Server 测试**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/gateway-store.test.js test/gateway-routes.test.js
```

Expected: PASS.

---

## Task 3: Gateway Identify Metadata

**Files:**
- Modify: `gateways/openclaw/clawke/src/gateway.ts`
- Modify: `gateways/hermes/clawke/clawke_channel.py`

- [x] **Step 1: 修改 OpenClaw identify**

在 `gateways/openclaw/clawke/src/gateway.ts` 的 identify send 处改为：

```ts
ws!.send(JSON.stringify({
  type: GatewayMessageType.Identify,
  accountId: ctx.accountId,
  agentName: 'OpenClaw',
  gatewayType: 'openclaw',
  capabilities: ['chat', 'tasks', 'skills', 'models'],
}));
```

- [x] **Step 2: 修改 Hermes identify**

在 `gateways/hermes/clawke/clawke_channel.py` 的 identify send 处改为：

```py
await ws.send(json.dumps({
    "type": GatewayMessageType.Identify,
    "accountId": self.config.account_id,
    "agentName": "Hermes",
    "gatewayType": "hermes",
    "capabilities": ["chat", "tasks", "skills", "models"],
}))
```

- [x] **Step 3: 运行 gateway 相关测试**

Run:

```bash
cd gateways/openclaw/clawke && npm test
```

Expected: PASS if package test script exists. If no package test script exists, run the existing OpenClaw gateway test command used by this repo.

Run:

```bash
cd gateways/hermes/clawke && python -m pytest
```

Expected: PASS if pytest is available. If pytest is unavailable, run existing Hermes gateway tests with the project Python environment.

---

## Task 4: Client Drift Cache for Gateways

**Files:**
- Create: `client/lib/data/database/tables/gateways.drift`
- Modify: `client/lib/data/database/app_database.dart`
- Create: `client/lib/data/database/dao/gateway_dao.dart`
- Create: `client/lib/models/gateway_info.dart`
- Test: `client/test/data/database/gateway_dao_test.dart`

- [x] **Step 1: 写 GatewayDao failing test**

创建 `client/test/data/database/gateway_dao_test.dart`：

```dart
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late GatewayDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = GatewayDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upserts and watches online gateways only', () async {
    await dao.upsertGateway(GatewaysCompanion(
      gatewayId: const Value('hermes'),
      displayName: const Value('Hermes'),
      gatewayType: const Value('hermes'),
      status: const Value('online'),
      capabilitiesJson: const Value('["tasks","skills"]'),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
    await dao.upsertGateway(GatewaysCompanion(
      gatewayId: const Value('offline'),
      displayName: const Value('Offline'),
      gatewayType: const Value('hermes'),
      status: const Value('disconnected'),
      capabilitiesJson: const Value('["tasks"]'),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));

    final online = await dao.getOnlineGateways();
    expect(online.map((item) => item.gatewayId), ['hermes']);
  });

  test('deleteMissing removes gateways not returned by server', () async {
    await dao.upsertGateway(GatewaysCompanion(
      gatewayId: const Value('old'),
      displayName: const Value('Old'),
      gatewayType: const Value('hermes'),
      status: const Value('online'),
      capabilitiesJson: const Value('["tasks"]'),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));

    await dao.deleteMissing({'hermes'});
    expect(await dao.getGateway('old'), isNull);
  });
}
```

- [x] **Step 2: 运行测试，确认失败**

Run:

```bash
cd client && flutter test test/data/database/gateway_dao_test.dart
```

Expected: FAIL，因为 `GatewayDao` 和 `gateways` 表不存在。

- [x] **Step 3: 创建 Drift 表**

创建 `client/lib/data/database/tables/gateways.drift`：

```sql
CREATE TABLE gateways (
    gateway_id          TEXT    NOT NULL PRIMARY KEY,
    display_name        TEXT    NOT NULL,
    gateway_type        TEXT    NOT NULL,
    status              TEXT    NOT NULL DEFAULT 'disconnected',
    capabilities_json   TEXT    NOT NULL DEFAULT '[]',
    last_error_code     TEXT,
    last_error_message  TEXT,
    last_connected_at   INTEGER,
    last_seen_at        INTEGER,
    created_at          INTEGER NOT NULL,
    updated_at          INTEGER NOT NULL
);

watchAllGateways:
  SELECT * FROM gateways
  ORDER BY display_name COLLATE NOCASE, gateway_id;

watchOnlineGateways:
  SELECT * FROM gateways
  WHERE status = 'online'
  ORDER BY display_name COLLATE NOCASE, gateway_id;

getGateway:
  SELECT * FROM gateways
  WHERE gateway_id = :gatewayId;
```

- [x] **Step 4: 修改 AppDatabase**

修改 `client/lib/data/database/app_database.dart`：

```dart
@DriftDatabase(include: {
  'tables/conversations.drift',
  'tables/messages.drift',
  'tables/metadata.drift',
  'tables/gateways.drift',
})
```

把 schemaVersion 加 1：

```dart
int get schemaVersion => 8;
```

在 migration `onUpgrade` 末尾加入：

```dart
      if (from < 8) {
        await m.createTable(gateways);
      }
```

- [x] **Step 5: 实现 GatewayDao**

创建 `client/lib/data/database/dao/gateway_dao.dart`：

```dart
import 'package:client/data/database/app_database.dart';
import 'package:drift/drift.dart';

class GatewayDao {
  final AppDatabase _db;
  GatewayDao(this._db);

  Stream<List<Gateway>> watchAll() => _db.watchAllGateways().watch();

  Stream<List<Gateway>> watchOnline() => _db.watchOnlineGateways().watch();

  Future<List<Gateway>> getOnlineGateways() => _db.watchOnlineGateways().get();

  Future<Gateway?> getGateway(String gatewayId) =>
      _db.getGateway(gatewayId).getSingleOrNull();

  Future<void> upsertGateway(GatewaysCompanion entry) {
    return _db.into(_db.gateways).insertOnConflictUpdate(entry);
  }

  Future<void> deleteMissing(Set<String> serverIds) async {
    final existing = await _db.watchAllGateways().get();
    for (final gateway in existing) {
      if (!serverIds.contains(gateway.gatewayId)) {
        await (_db.delete(_db.gateways)
              ..where((t) => t.gatewayId.equals(gateway.gatewayId)))
            .go();
      }
    }
  }
}
```

- [x] **Step 6: 生成 Drift 代码**

Run:

```bash
cd client && dart run build_runner build --delete-conflicting-outputs
```

Expected: generated files updated.

- [x] **Step 7: 运行测试**

Run:

```bash
cd client && flutter test test/data/database/gateway_dao_test.dart
```

Expected: PASS.

---

## Task 5: Client Gateway Repository and API

**Files:**
- Create: `client/lib/models/gateway_info.dart`
- Create: `client/lib/services/gateways_api_service.dart`
- Create: `client/lib/data/repositories/gateway_repository.dart`
- Modify: `client/lib/providers/database_providers.dart`
- Create: `client/lib/providers/gateway_provider.dart`
- Test: `client/test/providers/gateway_repository_test.dart`

- [x] **Step 1: 写 repository failing test**

创建 `client/test/providers/gateway_repository_test.dart`：

```dart
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:client/data/repositories/gateway_repository.dart';
import 'package:client/models/gateway_info.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGatewayApi implements GatewaysApi {
  List<GatewayInfo> items = const [];
  String? renamedId;
  String? renamedName;

  @override
  Future<List<GatewayInfo>> listGateways() async => items;

  @override
  Future<void> renameGateway(String gatewayId, String displayName) async {
    renamedId = gatewayId;
    renamedName = displayName;
  }
}

void main() {
  test('sync upserts server gateways and deletes missing local rows', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final api = FakeGatewayApi()
      ..items = const [
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['tasks', 'skills'],
        ),
      ];
    final repo = GatewayRepository(dao: GatewayDao(db), api: api);

    await repo.markOnline(const GatewayInfo(
      gatewayId: 'old',
      displayName: 'Old',
      gatewayType: 'hermes',
      status: GatewayConnectionStatus.online,
      capabilities: ['tasks'],
    ));

    await repo.syncFromServer();
    final online = await repo.getOnlineGateways();
    expect(online.map((item) => item.gatewayId), ['hermes']);
    await db.close();
  });

  test('rename is server first then syncs', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final api = FakeGatewayApi()
      ..items = const [
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Personal Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['tasks'],
        ),
      ];
    final repo = GatewayRepository(dao: GatewayDao(db), api: api);

    await repo.renameGateway('hermes', 'Personal Hermes');
    expect(api.renamedId, 'hermes');
    expect(api.renamedName, 'Personal Hermes');
    await db.close();
  });
}
```

- [x] **Step 2: 运行测试，确认失败**

Run:

```bash
cd client && flutter test test/providers/gateway_repository_test.dart
```

Expected: FAIL，因为 repository/API/model 不存在。

- [x] **Step 3: 创建 GatewayInfo model**

创建 `client/lib/models/gateway_info.dart`：

```dart
enum GatewayConnectionStatus { online, disconnected, error }

class GatewayInfo {
  final String gatewayId;
  final String displayName;
  final String gatewayType;
  final GatewayConnectionStatus status;
  final List<String> capabilities;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final int? lastConnectedAt;
  final int? lastSeenAt;

  const GatewayInfo({
    required this.gatewayId,
    required this.displayName,
    required this.gatewayType,
    required this.status,
    this.capabilities = const [],
    this.lastErrorCode,
    this.lastErrorMessage,
    this.lastConnectedAt,
    this.lastSeenAt,
  });

  factory GatewayInfo.fromJson(Map<String, dynamic> json) {
    return GatewayInfo(
      gatewayId: json['gateway_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? json['gateway_id'] as String? ?? '',
      gatewayType: json['gateway_type'] as String? ?? 'unknown',
      status: _statusFromString(json['status'] as String?),
      capabilities: (json['capabilities'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      lastErrorCode: json['last_error_code'] as String?,
      lastErrorMessage: json['last_error_message'] as String?,
      lastConnectedAt: json['last_connected_at'] as int?,
      lastSeenAt: json['last_seen_at'] as int?,
    );
  }

  bool supports(String capability) => capabilities.contains(capability);
}

GatewayConnectionStatus _statusFromString(String? value) {
  return switch (value) {
    'online' => GatewayConnectionStatus.online,
    'error' => GatewayConnectionStatus.error,
    _ => GatewayConnectionStatus.disconnected,
  };
}
```

- [x] **Step 4: 创建 API service**

创建 `client/lib/services/gateways_api_service.dart`：

```dart
import 'package:client/core/http_client.dart';
import 'package:client/models/gateway_info.dart';
import 'package:dio/dio.dart';

abstract class GatewaysApi {
  Future<List<GatewayInfo>> listGateways();
  Future<void> renameGateway(String gatewayId, String displayName);
}

class GatewaysApiService implements GatewaysApi {
  final Dio _dio;

  GatewaysApiService({Dio? dio}) : _dio = dio ?? createDio();

  @override
  Future<List<GatewayInfo>> listGateways() async {
    final response = await _dio.get('/api/gateways');
    final data = response.data as Map<String, dynamic>;
    final list = data['gateways'] as List? ?? const [];
    return list
        .map((item) => GatewayInfo.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  @override
  Future<void> renameGateway(String gatewayId, String displayName) async {
    await _dio.patch('/api/gateways/$gatewayId', data: {
      'display_name': displayName,
    });
  }
}
```

- [x] **Step 5: 创建 GatewayRepository**

创建 `client/lib/data/repositories/gateway_repository.dart`：

```dart
import 'dart:convert';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/services/gateways_api_service.dart';
import 'package:drift/drift.dart';

class GatewayRepository {
  final GatewayDao _dao;
  final GatewaysApi _api;

  GatewayRepository({required GatewayDao dao, required GatewaysApi api})
      : _dao = dao,
        _api = api;

  Stream<List<GatewayInfo>> watchAll() => _dao.watchAll().map(_fromRows);

  Stream<List<GatewayInfo>> watchOnline() => _dao.watchOnline().map(_fromRows);

  Future<List<GatewayInfo>> getOnlineGateways() async =>
      _fromRows(await _dao.getOnlineGateways());

  Future<void> syncFromServer() async {
    final gateways = await _api.listGateways();
    final ids = <String>{};
    for (final gateway in gateways) {
      ids.add(gateway.gatewayId);
      await _dao.upsertGateway(_toCompanion(gateway));
    }
    await _dao.deleteMissing(ids);
  }

  Future<void> markOnline(GatewayInfo gateway) {
    return _dao.upsertGateway(_toCompanion(gateway));
  }

  Future<void> markOffline(String gatewayId) async {
    final existing = await _dao.getGateway(gatewayId);
    if (existing == null) return;
    await _dao.upsertGateway(existing.toCompanion(false).copyWith(
      status: const Value('disconnected'),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> renameGateway(String gatewayId, String displayName) async {
    await _api.renameGateway(gatewayId, displayName);
    await syncFromServer();
  }

  List<GatewayInfo> _fromRows(List<Gateway> rows) {
    return rows.map((row) {
      return GatewayInfo(
        gatewayId: row.gatewayId,
        displayName: row.displayName,
        gatewayType: row.gatewayType,
        status: _statusFromString(row.status),
        capabilities: _decodeCapabilities(row.capabilitiesJson),
        lastErrorCode: row.lastErrorCode,
        lastErrorMessage: row.lastErrorMessage,
        lastConnectedAt: row.lastConnectedAt,
        lastSeenAt: row.lastSeenAt,
      );
    }).toList();
  }

  GatewaysCompanion _toCompanion(GatewayInfo gateway) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return GatewaysCompanion(
      gatewayId: Value(gateway.gatewayId),
      displayName: Value(gateway.displayName),
      gatewayType: Value(gateway.gatewayType),
      status: Value(_statusToString(gateway.status)),
      capabilitiesJson: Value(jsonEncode(gateway.capabilities)),
      lastErrorCode: Value(gateway.lastErrorCode),
      lastErrorMessage: Value(gateway.lastErrorMessage),
      lastConnectedAt: Value(gateway.lastConnectedAt),
      lastSeenAt: Value(gateway.lastSeenAt),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }
}

List<String> _decodeCapabilities(String raw) {
  try {
    return (jsonDecode(raw) as List).map((item) => item.toString()).toList();
  } catch (_) {
    return const [];
  }
}

GatewayConnectionStatus _statusFromString(String value) {
  return switch (value) {
    'online' => GatewayConnectionStatus.online,
    'error' => GatewayConnectionStatus.error,
    _ => GatewayConnectionStatus.disconnected,
  };
}

String _statusToString(GatewayConnectionStatus status) {
  return switch (status) {
    GatewayConnectionStatus.online => 'online',
    GatewayConnectionStatus.error => 'error',
    GatewayConnectionStatus.disconnected => 'disconnected',
  };
}
```

- [x] **Step 6: 注册 providers**

修改 `client/lib/providers/database_providers.dart`：

```dart
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:client/data/repositories/gateway_repository.dart';
import 'package:client/services/gateways_api_service.dart';
```

加入：

```dart
final gatewaysApiServiceProvider = Provider<GatewaysApiService>((ref) {
  return GatewaysApiService();
});

final gatewayDaoProvider = Provider<GatewayDao>((ref) {
  return GatewayDao(ref.watch(databaseProvider));
});

final gatewayRepositoryProvider = Provider<GatewayRepository>((ref) {
  return GatewayRepository(
    dao: ref.watch(gatewayDaoProvider),
    api: ref.watch(gatewaysApiServiceProvider),
  );
});
```

创建 `client/lib/providers/gateway_provider.dart`：

```dart
import 'package:client/models/gateway_info.dart';
import 'package:client/providers/database_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final gatewayListProvider = StreamProvider<List<GatewayInfo>>((ref) {
  return ref.watch(gatewayRepositoryProvider).watchAll();
});

final onlineGatewayListProvider = StreamProvider<List<GatewayInfo>>((ref) {
  return ref.watch(gatewayRepositoryProvider).watchOnline();
});

final selectedGatewayIdProvider = StateProvider<String?>((ref) => null);

final selectedGatewayProvider = Provider<GatewayInfo?>((ref) {
  final selectedId = ref.watch(selectedGatewayIdProvider);
  final gateways = ref.watch(onlineGatewayListProvider).valueOrNull ?? const [];
  if (selectedId == null) return gateways.firstOrNull;
  return gateways.where((item) => item.gatewayId == selectedId).firstOrNull;
});
```

- [x] **Step 7: 运行 Repository 测试**

Run:

```bash
cd client && flutter test test/providers/gateway_repository_test.dart
```

Expected: PASS.

---

## Task 6: WS Status Integration

**Files:**
- Modify: `client/lib/core/cup_parser.dart`
- Modify: `client/lib/models/message_model.dart`
- Modify: `client/lib/providers/chat_provider.dart`
- Test: update existing chat provider system status tests if present.

- [x] **Step 1: 扩展 SystemMessage**

在 `client/lib/models/message_model.dart` 的 `SystemMessage` 增加：

```dart
final String? gatewayType;
final List<String> capabilities;
```

构造函数默认：

```dart
this.gatewayType,
this.capabilities = const [],
```

- [x] **Step 2: 扩展 CupParser**

修改 `client/lib/core/cup_parser.dart` system_status parse：

```dart
gatewayType: json['gateway_type'] as String?,
capabilities: (json['capabilities'] as List? ?? const [])
    .map((item) => item.toString())
    .toList(),
```

- [x] **Step 3: chat_provider 写入 GatewayRepository**

修改 `client/lib/providers/chat_provider.dart` 的 `ai_connected` 分支，在现有 `connectedAccountsProvider` 更新后加入：

```dart
await _ref.read(gatewayRepositoryProvider).markOnline(GatewayInfo(
  gatewayId: msg.accountId!,
  displayName: name,
  gatewayType: msg.gatewayType ?? 'unknown',
  status: GatewayConnectionStatus.online,
  capabilities: msg.capabilities.isEmpty
      ? const ['chat']
      : msg.capabilities,
  lastConnectedAt: DateTime.now().millisecondsSinceEpoch,
  lastSeenAt: DateTime.now().millisecondsSinceEpoch,
));
```

在 `ai_disconnected` 分支加入：

```dart
await _ref.read(gatewayRepositoryProvider).markOffline(msg.accountId!);
```

在 WebSocket 建连或收到首个状态后触发一次：

```dart
unawaited(_ref.read(gatewayRepositoryProvider).syncFromServer());
```

- [x] **Step 4: 运行 Flutter 测试**

Run:

```bash
cd client && flutter test test/providers test/data/database/gateway_dao_test.dart
```

Expected: PASS.

---

## Task 7: Shared GatewaySelectorPane

**Files:**
- Create: `client/lib/widgets/gateway_selector_pane.dart`
- Test: `client/test/widgets/gateway_selector_pane_test.dart`

- [x] **Step 1: 写 widget failing test**

创建 `client/test/widgets/gateway_selector_pane_test.dart`：

```dart
import 'package:client/models/gateway_info.dart';
import 'package:client/widgets/gateway_selector_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders only online gateways matching capability', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: GatewaySelectorPane(
        gateways: const [
          GatewayInfo(
            gatewayId: 'hermes',
            displayName: 'Hermes',
            gatewayType: 'hermes',
            status: GatewayConnectionStatus.online,
            capabilities: ['tasks'],
          ),
          GatewayInfo(
            gatewayId: 'skills-only',
            displayName: 'Skills',
            gatewayType: 'hermes',
            status: GatewayConnectionStatus.online,
            capabilities: ['skills'],
          ),
          GatewayInfo(
            gatewayId: 'offline',
            displayName: 'Offline',
            gatewayType: 'hermes',
            status: GatewayConnectionStatus.disconnected,
            capabilities: ['tasks'],
          ),
        ],
        selectedGatewayId: 'hermes',
        capability: 'tasks',
        onSelected: selected.add,
        onRename: (_, __) async {},
      ),
    ));

    expect(find.text('Hermes'), findsOneWidget);
    expect(find.text('Skills'), findsNothing);
    expect(find.text('Offline'), findsNothing);
  });
}
```

- [x] **Step 2: 运行测试，确认失败**

Run:

```bash
cd client && flutter test test/widgets/gateway_selector_pane_test.dart
```

Expected: FAIL，因为 widget 不存在。

- [x] **Step 3: 创建共享 widget**

创建 `client/lib/widgets/gateway_selector_pane.dart`：

```dart
import 'package:client/models/gateway_info.dart';
import 'package:flutter/material.dart';

class GatewaySelectorPane extends StatelessWidget {
  final List<GatewayInfo> gateways;
  final String? selectedGatewayId;
  final String capability;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String gatewayId, String displayName) onRename;
  final String? errorGatewayId;

  const GatewaySelectorPane({
    super.key,
    required this.gateways,
    required this.selectedGatewayId,
    required this.capability,
    required this.onSelected,
    required this.onRename,
    this.errorGatewayId,
  });

  @override
  Widget build(BuildContext context) {
    final visible = gateways
        .where((item) =>
            item.status == GatewayConnectionStatus.online &&
            item.supports(capability))
        .toList();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Gateway 列表',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Text(
              '暂无已连接 Gateway',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            )
          else
            for (final gateway in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GatewayTile(
                  gateway: gateway,
                  selected: gateway.gatewayId == selectedGatewayId,
                  hasIssue: gateway.gatewayId == errorGatewayId,
                  onSelected: onSelected,
                  onRename: onRename,
                ),
              ),
        ],
      ),
    );
  }
}

class _GatewayTile extends StatelessWidget {
  final GatewayInfo gateway;
  final bool selected;
  final bool hasIssue;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String gatewayId, String displayName) onRename;

  const _GatewayTile({
    required this.gateway,
    required this.selected,
    required this.hasIssue,
    required this.onSelected,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapUp: (details) => _showMenu(context, details.globalPosition),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => onSelected(gateway.gatewayId),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.hub_outlined,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gateway.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        gateway.gatewayId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: selected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (hasIssue)
                  Icon(Icons.priority_high_rounded, color: colorScheme.error),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('重命名')),
      ],
    ).then((value) {
      if (value == 'rename' && context.mounted) {
        _showRename(context);
      }
    });
  }

  void _showRename(BuildContext context) {
    final controller = TextEditingController(text: gateway.displayName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名 Gateway'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (_) => _submitRename(ctx, controller),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => _submitRename(ctx, controller),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _submitRename(BuildContext ctx, TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return;
    onRename(gateway.gatewayId, value);
    Navigator.of(ctx).pop();
  }
}
```

- [x] **Step 4: 运行 widget 测试**

Run:

```bash
cd client && flutter test test/widgets/gateway_selector_pane_test.dart
```

Expected: PASS.

---

## Task 8: Replace Task and Skill Local Gateway Sidebars

**Files:**
- Modify: `client/lib/screens/tasks_management_screen.dart`
- Modify: `client/lib/providers/tasks_provider.dart`
- Modify: `client/lib/screens/skills_management_screen.dart`
- Modify: `client/lib/providers/skills_provider.dart`
- Test: update `client/test/tasks_management_screen_test.dart`
- Test: update `client/test/skills_management_screen_test.dart`

- [x] **Step 1: 更新任务页接入方式**

在 `TasksManagementScreen` 中：

```dart
final gateways = ref.watch(onlineGatewayListProvider).valueOrNull ?? const [];
```

替换 `_GatewaySidebar`：

```dart
GatewaySelectorPane(
  gateways: gateways,
  selectedGatewayId: state.selectedAccountId,
  capability: 'tasks',
  errorGatewayId: state.errorAccountId,
  onSelected: _selectAccount,
  onRename: (gatewayId, displayName) =>
      ref.read(gatewayRepositoryProvider).renameGateway(gatewayId, displayName),
),
```

删除任务页内部 `_GatewaySidebar`、`_GatewayTile`、`_MobileGatewaySelector`。

- [x] **Step 2: 更新任务 provider**

`TasksController.syncAccounts` 可以保留接口，但调用方传入从 `GatewayInfo` 映射出的 `TaskAccount`：

```dart
TaskAccount(accountId: gateway.gatewayId, agentName: gateway.displayName)
```

后续清理时再把 `TaskAccount` 直接替换成 `GatewayInfo`，本任务只做最小改动。

- [x] **Step 3: 更新技能页接入方式**

`SkillsManagementScreen` 使用：

```dart
GatewaySelectorPane(
  gateways: gateways,
  selectedGatewayId: state.selectedScope?.gatewayId,
  capability: 'skills',
  onSelected: (gatewayId) => ref.read(skillsControllerProvider.notifier).selectGateway(gatewayId),
  onRename: (gatewayId, displayName) =>
      ref.read(gatewayRepositoryProvider).renameGateway(gatewayId, displayName),
),
```

删除技能页内部 `_ScopeSidebar`、`_ScopeTile`、`_MobileScopeSelector`。

- [x] **Step 4: 更新技能 provider**

在 `SkillsController` 增加：

```dart
Future<void> selectGateway(String gatewayId) async {
  final scope = SkillScope(
    id: 'gateway:$gatewayId',
    type: 'gateway',
    label: gatewayId,
    description: 'Gateway',
    readonly: false,
    gatewayId: gatewayId,
  );
  state = state.copyWith(selectedScopeId: scope.id, isLoading: true, clearError: true);
  try {
    final skills = await _api.listSkills(scope: scope);
    state = state.copyWith(skills: skills, isLoading: false);
  } catch (e) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: _skillErrorMessage(e, scope: scope),
    );
  }
}
```

保留 `/api/skills/scopes` 兼容逻辑一轮迭代，后续删除。

- [x] **Step 5: 更新页面测试**

更新任务页和技能页测试断言：

```dart
expect(find.text('Hermes'), findsOneWidget);
expect(find.text('offline'), findsNothing);
```

新增右键重命名测试：

```dart
await tester.tap(find.text('Hermes'), buttons: kSecondaryButton);
await tester.pumpAndSettle();
expect(find.text('重命名'), findsOneWidget);
```

- [x] **Step 6: 运行页面测试**

Run:

```bash
cd client && flutter test test/tasks_management_screen_test.dart test/skills_management_screen_test.dart test/widgets/gateway_selector_pane_test.dart
```

Expected: PASS.

---

## Task 9: End-to-End Verification

**Files:**
- No new files.

- [ ] **Step 1: Server test suite**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit
```

Expected: PASS.

Status: attempted on 2026-04-25. Sandbox run failed on local socket EPERM; escalated run reached existing E2E/abort tests and failed/hung outside this task's Gateway cache path. Targeted Gateway/task/skill server tests passed:

```bash
cd server && npm run build
cd server && node --test --test-concurrency=1 --test-force-exit test/gateway-store.test.js test/gateway-routes.test.js test/task-gateway-client.test.js test/tasks-routes.test.js test/skill-gateway-client.test.js test/skills-routes.test.js
```

- [x] **Step 2: Flutter targeted tests**

Run:

```bash
cd client && flutter test test/data/database/gateway_dao_test.dart test/providers/gateway_repository_test.dart test/widgets/gateway_selector_pane_test.dart test/tasks_management_screen_test.dart test/skills_management_screen_test.dart
```

Expected: PASS.

- [x] **Step 3: Flutter analyze**

Run:

```bash
cd client && dart analyze lib/data/database lib/data/repositories lib/providers lib/services lib/widgets/gateway_selector_pane.dart lib/screens/tasks_management_screen.dart lib/screens/skills_management_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Manual verification**

Start Server and Gateway using the existing local commands. Then verify:

```text
1. Open task management page.
2. Only connected gateways are visible.
3. Stop Hermes gateway.
4. Hermes disappears from task/skill gateway list after sync or disconnect event.
5. Keep Hermes configured but stopped.
6. GET /api/gateways returns Hermes with status=disconnected.
7. Remove Hermes from ~/.clawke/clawke.json and restart Server.
8. GET /api/gateways no longer returns Hermes.
9. Client deletes Hermes cache after sync.
10. Right-click online Gateway, rename it.
11. Rename calls Server first and UI updates after sync.
```

Expected: all checks match.

Status: not executed in this turn. Requires live local Server + Gateway lifecycle testing.

---

## Completion Criteria

- `/api/gateways` returns configured disconnected gateways and connected online gateways.
- Server no longer hardcodes every connected gateway as `OpenClaw`.
- Server does not return DB-only stale gateways.
- Client deletes cached gateways absent from Server response.
- Task management and skills center use one shared Gateway selector widget.
- Task management and skills center show only online gateways.
- Gateway right-click rename is Server-first and syncs back to DB.
- Targeted server and Flutter tests pass.
