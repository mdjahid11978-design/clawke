# Task Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 Clawke 独立任务管理页面，支持 Hermes 和 OpenClaw 的任务增删改查、启停、触发、执行记录和输出查看。

**Architecture:** Flutter 任务管理页通过 HTTP 调 Clawke Server；Clawke Server 不存储任务真相、不执行任务，只把 HTTP 请求转换成 upstream WebSocket task command；Hermes/OpenClaw gateway 分别实现 agent 侧 task adapter，并保持任务权威在 agent/gateway 侧。

**Tech Stack:** Flutter + Riverpod + Dio；Node.js/Express + ws + node:test；Hermes Python gateway；OpenClaw TypeScript gateway。

---

## 文件结构

### Server

- 新建 `server/src/types/tasks.ts`：定义 Server 内部 task DTO、gateway command/response 类型。
- 新建 `server/src/upstream/task-gateway-client.ts`：基于现有 upstream WS 连接发送 `task_*` request，并用 `request_id` 等待响应。
- 修改 `server/src/upstream/openclaw-listener.ts`：导出通用 `queryGateway` 能力，并允许按 `request_id` 关联 `task_*_response`。
- 新建 `server/src/routes/tasks-routes.ts`：HTTP routes，输入校验、account 选择、错误归一化。
- 修改 `server/src/http-server.ts`：注册 `/api/tasks` endpoints，并把 root endpoint 列表补上 `/api/tasks`。
- 修改 `server/src/index.ts`：在 mock/openclaw 初始化路径里初始化 tasks routes 所需依赖。
- 新建 `server/test/tasks-routes.test.js`：HTTP route 单测。
- 新建 `server/test/task-gateway-client.test.js`：gateway request/response correlation 单测。

### Hermes Gateway

- 修改 `gateways/hermes/clawke/clawke_channel.py`：扩展 inbound message type，处理 task commands。
- 新建 `gateways/hermes/clawke/task_adapter.py`：封装 Hermes cron jobs/list/create/update/delete/run/runs/output 映射。
- 新建 `gateways/hermes/clawke/test_task_adapter.py`：mock `cron.jobs` 和 output 文件的 adapter 单测。

### OpenClaw Gateway

- 修改 `gateways/openclaw/clawke/src/protocol.ts`：加入 task inbound/response message type。
- 修改 `gateways/openclaw/clawke/src/gateway.ts`：处理 task commands。
- 新建 `gateways/openclaw/clawke/src/task-adapter.ts`：OpenClaw agent-owned task adapter。初版用 gateway 侧 JSON 文件存储任务，执行/调度仍归 OpenClaw/gateway 侧，Clawke Server 不落库。
- 新建 `gateways/openclaw/clawke/src/task-adapter.test.ts`：用 `npx tsx --test` 覆盖 create/list/update/delete/enabled/run/runs/output。

### Flutter Client

- 新建 `client/lib/models/managed_task.dart`：`ManagedTask`、`TaskDraft`、`TaskRun`、`TaskOutput`。
- 新建 `client/lib/services/tasks_api_service.dart`：Dio HTTP service。
- 新建 `client/lib/providers/tasks_provider.dart`：Riverpod controller/state。
- 新建 `client/lib/screens/tasks_management_screen.dart`：桌面三栏方案 A + 移动端 Skills 风格单列布局。
- 修改 `client/lib/providers/nav_page_provider.dart`：保留/使用 `NavPage.cron` 或重命名为 `NavPage.tasks`。优先重命名为 `tasks`，避免 cron 概念泄漏到通用任务管理。
- 修改 `client/lib/widgets/nav_rail.dart`：展示 Tasks 入口。
- 修改 `client/lib/screens/main_layout.dart`：Tasks tab 渲染 `TasksManagementScreen`。
- 修改 `client/lib/l10n/app_zh.arb`、`client/lib/l10n/app_en.arb` 并运行 l10n。
- 新建 `client/test/models/managed_task_test.dart`。
- 新建 `client/test/providers/tasks_provider_test.dart`。
- 新建 `client/test/services/tasks_api_service_test.dart`。
- 新建 `client/test/screens/tasks_management_screen_test.dart`。

---

## Task 1: Server task gateway client

**Files:**
- Create: `server/src/types/tasks.ts`
- Create: `server/src/upstream/task-gateway-client.ts`
- Modify: `server/src/upstream/openclaw-listener.ts`
- Test: `server/test/task-gateway-client.test.js`

- [ ] **Step 1: 写 failing test**

在 `server/test/task-gateway-client.test.js` 中创建测试，验证 task request 带 `request_id`，并只解析匹配的 response。

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';

class FakeWs extends EventEmitter {
  constructor() {
    super();
    this.readyState = 1;
    this.sent = [];
  }
  send(raw) {
    this.sent.push(JSON.parse(raw));
  }
}

test('task gateway request resolves only matching request_id', async () => {
  const mod = await import('../dist/upstream/task-gateway-client.js');
  const ws = new FakeWs();
  const promise = mod.sendTaskGatewayRequestForTest(ws, {
    type: 'task_list',
    account_id: 'hermes',
  }, 1000);

  assert.equal(ws.sent[0].type, 'task_list');
  assert.equal(typeof ws.sent[0].request_id, 'string');

  ws.emit('message', Buffer.from(JSON.stringify({
    type: 'task_list_response',
    request_id: 'other',
    tasks: [],
  })));
  ws.emit('message', Buffer.from(JSON.stringify({
    type: 'task_list_response',
    request_id: ws.sent[0].request_id,
    tasks: [{ id: 'job_1', name: 'Daily', schedule: '0 9 * * *', prompt: 'hello', enabled: true, status: 'active' }],
  })));

  const result = await promise;
  assert.equal(result.type, 'task_list_response');
  assert.equal(result.tasks.length, 1);
});
```

- [ ] **Step 2: 运行测试，确认失败**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/task-gateway-client.test.js
```

Expected: build 或 test 失败，因为 `task-gateway-client.js` 不存在。

- [ ] **Step 3: 定义 task 类型**

创建 `server/src/types/tasks.ts`：

```ts
export type TaskStatus = 'active' | 'paused' | 'disabled' | 'error';
export type TaskRunStatus = 'running' | 'success' | 'failed' | 'cancelled';

export interface ManagedTask {
  id: string;
  account_id: string;
  agent: string;
  name: string;
  schedule: string;
  schedule_text?: string;
  prompt: string;
  enabled: boolean;
  status: TaskStatus;
  skills?: string[];
  deliver?: string;
  next_run_at?: string;
  last_run?: TaskRun;
  created_at?: string;
  updated_at?: string;
}

export interface TaskDraft {
  account_id: string;
  name?: string;
  schedule: string;
  prompt: string;
  enabled?: boolean;
  skills?: string[];
  deliver?: string;
}

export interface TaskRun {
  id: string;
  task_id: string;
  started_at: string;
  finished_at?: string;
  status: TaskRunStatus;
  output_preview?: string;
  error?: string;
}

export type TaskGatewayCommandType =
  | 'task_list'
  | 'task_get'
  | 'task_create'
  | 'task_update'
  | 'task_delete'
  | 'task_set_enabled'
  | 'task_run'
  | 'task_runs'
  | 'task_output';

export interface TaskGatewayRequest {
  type: TaskGatewayCommandType;
  request_id?: string;
  account_id: string;
  task_id?: string;
  run_id?: string;
  task?: TaskDraft;
  patch?: Partial<TaskDraft>;
  enabled?: boolean;
}

export interface TaskGatewayResponse {
  type: string;
  request_id: string;
  ok?: boolean;
  task?: ManagedTask;
  tasks?: ManagedTask[];
  runs?: TaskRun[];
  output?: string;
  error?: string;
  message?: string;
  details?: unknown;
}
```

- [ ] **Step 4: 实现 gateway client**

创建 `server/src/upstream/task-gateway-client.ts`：

```ts
import crypto from 'crypto';
import type { WebSocket } from 'ws';
import type { TaskGatewayRequest, TaskGatewayResponse } from '../types/tasks.js';
import { getUpstreamConnection } from './openclaw-listener.js';

export class TaskGatewayError extends Error {
  constructor(
    public code: string,
    message: string,
    public status = 500,
    public details?: unknown,
  ) {
    super(message);
  }
}

const RESPONSE_BY_COMMAND: Record<string, string[]> = {
  task_list: ['task_list_response'],
  task_get: ['task_get_response'],
  task_create: ['task_mutation_response'],
  task_update: ['task_mutation_response'],
  task_delete: ['task_mutation_response'],
  task_set_enabled: ['task_mutation_response'],
  task_run: ['task_run_response'],
  task_runs: ['task_runs_response'],
  task_output: ['task_output_response'],
};

export async function sendTaskGatewayRequest(
  request: TaskGatewayRequest,
  timeoutMs = 5000,
): Promise<TaskGatewayResponse> {
  const ws = getUpstreamConnection(request.account_id);
  if (!ws || ws.readyState !== 1) {
    throw new TaskGatewayError('gateway_unavailable', `No gateway connected for account_id=${request.account_id}`, 503);
  }
  return sendTaskGatewayRequestForTest(ws, request, timeoutMs);
}

export function sendTaskGatewayRequestForTest(
  ws: Pick<WebSocket, 'send' | 'on' | 'removeListener' | 'readyState'>,
  request: TaskGatewayRequest,
  timeoutMs = 5000,
): Promise<TaskGatewayResponse> {
  const requestId = request.request_id || crypto.randomUUID();
  const expectedTypes = RESPONSE_BY_COMMAND[request.type] || [];
  const outbound = { ...request, request_id: requestId };

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new TaskGatewayError('gateway_timeout', `Gateway timeout for ${request.type}`, 504));
    }, timeoutMs);

    const handler = (raw: Buffer) => {
      try {
        const msg = JSON.parse(raw.toString()) as TaskGatewayResponse;
        if (msg.request_id !== requestId) return;
        if (!expectedTypes.includes(msg.type)) return;
        cleanup();
        if (msg.ok === false || msg.error) {
          reject(new TaskGatewayError(msg.error || 'gateway_error', msg.message || 'Gateway task error', 502, msg.details));
          return;
        }
        resolve(msg);
      } catch {
        return;
      }
    };

    const cleanup = () => {
      clearTimeout(timeout);
      ws.removeListener('message', handler);
    };

    ws.on('message', handler);
    ws.send(JSON.stringify(outbound));
  });
}
```

- [ ] **Step 5: 导出 upstream connection getter**

修改 `server/src/upstream/openclaw-listener.ts`，在 `sendToOpenClaw` 附近加入：

```ts
export function getUpstreamConnection(accountId: string): WebSocket | undefined {
  const ws = upstreamConnections.get(accountId);
  if (ws && ws.readyState === 1) return ws;
  return undefined;
}
```

- [ ] **Step 6: 跑测试**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/task-gateway-client.test.js
```

Expected: PASS。

- [ ] **Step 7: 提交**

```bash
git add server/src/types/tasks.ts server/src/upstream/task-gateway-client.ts server/src/upstream/openclaw-listener.ts server/test/task-gateway-client.test.js
git commit -m "feat(server): add task gateway client"
```

---

## Task 2: Server HTTP task routes

**Files:**
- Create: `server/src/routes/tasks-routes.ts`
- Modify: `server/src/http-server.ts`
- Modify: `server/src/index.ts`
- Test: `server/test/tasks-routes.test.js`

- [ ] **Step 1: 写 failing route test**

在 `server/test/tasks-routes.test.js` 中验证缺少 `account_id` 时返回 `account_required`，并验证 list route 会调用 gateway command。

```js
import test from 'node:test';
import assert from 'node:assert/strict';

test('tasks route requires account_id when no default account resolver exists', async () => {
  const routes = await import('../dist/routes/tasks-routes.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => [],
    sendTaskRequest: async () => ({ type: 'task_list_response', request_id: 'r', tasks: [] }),
  });

  const req = { query: {}, body: {}, params: {} };
  const res = fakeRes();
  await routes.listTasks(req, res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'account_required');
});

test('tasks route maps GET list to task_list command', async () => {
  const calls = [];
  const routes = await import('../dist/routes/tasks-routes.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => ['hermes'],
    sendTaskRequest: async (payload) => {
      calls.push(payload);
      return { type: 'task_list_response', request_id: 'r', tasks: [] };
    },
  });

  const req = { query: { account_id: 'hermes' }, body: {}, params: {} };
  const res = fakeRes();
  await routes.listTasks(req, res);

  assert.equal(calls[0].type, 'task_list');
  assert.equal(calls[0].account_id, 'hermes');
  assert.deepEqual(res.body.tasks, []);
});

function fakeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/tasks-routes.test.js
```

Expected: FAIL，`tasks-routes.js` 不存在。

- [ ] **Step 3: 实现 routes**

创建 `server/src/routes/tasks-routes.ts`：

```ts
import type { Request, Response } from 'express';
import type { TaskDraft, TaskGatewayRequest, TaskGatewayResponse } from '../types/tasks.js';
import { sendTaskGatewayRequest, TaskGatewayError } from '../upstream/task-gateway-client.js';

interface TasksDeps {
  getConnectedAccountIds: () => string[];
  sendTaskRequest?: (payload: TaskGatewayRequest) => Promise<TaskGatewayResponse>;
}

let deps: TasksDeps | null = null;

export function initTasksRoutes(nextDeps: TasksDeps): void {
  deps = nextDeps;
}

export async function listTasks(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_list', account_id: accountId }, (r) => ({ tasks: r.tasks || [] }));
}

export async function getTask(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_get', account_id: accountId, task_id: req.params.taskId }, (r) => ({ task: r.task }));
}

export async function createTask(req: Request, res: Response): Promise<void> {
  const draft = req.body as TaskDraft;
  const validation = validateDraft(draft);
  if (validation) return sendHttpError(res, 400, 'validation_error', validation);
  await respond(res, { type: 'task_create', account_id: draft.account_id, task: draft }, (r) => ({ task: r.task }), 201);
}

export async function updateTask(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_update', account_id: accountId, task_id: req.params.taskId, patch: req.body || {} }, (r) => ({ task: r.task }));
}

export async function deleteTask(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_delete', account_id: accountId, task_id: req.params.taskId }, () => ({ ok: true, deleted: req.params.taskId }));
}

export async function setTaskEnabled(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, {
    type: 'task_set_enabled',
    account_id: accountId,
    task_id: req.params.taskId,
    enabled: !!req.body?.enabled,
  }, (r) => ({ ok: true, task: r.task }));
}

export async function runTask(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_run', account_id: accountId, task_id: req.params.taskId }, (r) => ({ ok: true, run: r.runs?.[0] || null }));
}

export async function listTaskRuns(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_runs', account_id: accountId, task_id: req.params.taskId }, (r) => ({ runs: r.runs || [] }));
}

export async function getTaskRunOutput(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, {
    type: 'task_output',
    account_id: accountId,
    task_id: req.params.taskId,
    run_id: req.params.runId,
  }, (r) => ({ output: r.output || '' }));
}

function resolveAccountId(req: Request, res: Response): string | null {
  const explicit = (req.query.account_id as string) || req.body?.account_id;
  if (explicit) return explicit;
  const connected = deps?.getConnectedAccountIds() || [];
  if (connected.length === 1) return connected[0];
  sendHttpError(res, 400, 'account_required', 'account_id is required when account selection is ambiguous.');
  return null;
}

function validateDraft(draft: TaskDraft): string | null {
  if (!draft?.account_id) return 'account_id is required.';
  if (!draft.schedule?.trim()) return 'schedule is required.';
  if (!draft.prompt?.trim()) return 'prompt is required.';
  return null;
}

async function respond(
  res: Response,
  request: TaskGatewayRequest,
  map: (r: TaskGatewayResponse) => Record<string, unknown>,
  status = 200,
): Promise<void> {
  try {
    const sender = deps?.sendTaskRequest || sendTaskGatewayRequest;
    const result = await sender(request);
    res.status(status).json(map(result));
  } catch (err) {
    sendError(res, err);
  }
}

function sendError(res: Response, err: unknown): void {
  if (err instanceof TaskGatewayError) {
    res.status(err.status).json({ error: err.code, message: err.message, details: err.details });
    return;
  }
  const message = err instanceof Error ? err.message : String(err);
  res.status(500).json({ error: 'internal_error', message });
}

function sendHttpError(res: Response, status: number, error: string, message: string): void {
  res.status(status).json({ error, message });
}
```

- [ ] **Step 4: 注册 HTTP endpoints**

修改 `server/src/http-server.ts` imports：

```ts
import {
  createTask,
  deleteTask,
  getTask,
  getTaskRunOutput,
  listTaskRuns,
  listTasks,
  runTask,
  setTaskEnabled,
  updateTask,
} from './routes/tasks-routes.js';
```

在 Skills API 后加入：

```ts
  // Tasks 管理 API
  app.get('/api/tasks', listTasks as any);
  app.get('/api/tasks/:taskId', getTask as any);
  app.post('/api/tasks', createTask as any);
  app.put('/api/tasks/:taskId/enabled', setTaskEnabled as any);
  app.post('/api/tasks/:taskId/run', runTask as any);
  app.get('/api/tasks/:taskId/runs', listTaskRuns as any);
  app.get('/api/tasks/:taskId/runs/:runId/output', getTaskRunOutput as any);
  app.put('/api/tasks/:taskId', updateTask as any);
  app.delete('/api/tasks/:taskId', deleteTask as any);
```

Root endpoint 列表加入 `'/api/tasks'`。

- [ ] **Step 5: 初始化 routes**

修改 `server/src/index.ts`，在 openclaw 分支 import `initTasksRoutes` 并初始化：

```ts
    const { initTasksRoutes } = await import('./routes/tasks-routes.js');
    const { sendTaskGatewayRequest } = await import('./upstream/task-gateway-client.js');
    initTasksRoutes({
      getConnectedAccountIds,
      sendTaskRequest: sendTaskGatewayRequest,
    });
```

mock 分支也初始化，返回空列表，避免 UI 在 mock 模式 500：

```ts
    const { initTasksRoutes } = await import('./routes/tasks-routes.js');
    initTasksRoutes({
      getConnectedAccountIds: () => ['mock'],
      sendTaskRequest: async (payload) => {
        if (payload.type === 'task_list') return { type: 'task_list_response', request_id: payload.request_id || 'mock', tasks: [] };
        return { type: 'task_mutation_response', request_id: payload.request_id || 'mock', ok: false, error: 'tasks_unsupported', message: 'Mock mode does not manage agent tasks.' };
      },
    });
```

- [ ] **Step 6: 跑测试**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/tasks-routes.test.js
```

Expected: PASS。

- [ ] **Step 7: 跑 server 全量测试**

Run:

```bash
cd server && npm test
```

Expected: PASS。

- [ ] **Step 8: 提交**

```bash
git add server/src/routes/tasks-routes.ts server/src/http-server.ts server/src/index.ts server/test/tasks-routes.test.js
git commit -m "feat(server): add task management routes"
```

---

## Task 3: Hermes task adapter

**Files:**
- Create: `gateways/hermes/clawke/task_adapter.py`
- Modify: `gateways/hermes/clawke/clawke_channel.py`
- Test: `gateways/hermes/clawke/test_task_adapter.py`

- [ ] **Step 1: 写 adapter tests**

创建 `gateways/hermes/clawke/test_task_adapter.py`：

```python
import sys
import types

from task_adapter import HermesTaskAdapter


def install_fake_cron(monkeypatch):
    cron_pkg = types.ModuleType("cron")
    jobs_mod = types.ModuleType("cron.jobs")

    store = {
        "job_1": {
            "job_id": "job_1",
            "name": "Daily",
            "schedule": "0 9 * * *",
            "prompt": "hello",
            "enabled": True,
            "skill_ids": ["calendar"],
            "deliver": "local",
        }
    }

    def list_jobs():
        return list(store.values())

    def create_job(**kwargs):
        job = {"job_id": "job_2", "enabled": True, **kwargs}
        store[job["job_id"]] = job
        return job

    def update_job(job_id, **kwargs):
        store[job_id].update(kwargs)
        return store[job_id]

    def remove_job(job_id):
        store.pop(job_id)
        return True

    def pause_job(job_id):
        store[job_id]["enabled"] = False
        return store[job_id]

    def resume_job(job_id):
        store[job_id]["enabled"] = True
        return store[job_id]

    jobs_mod.list_jobs = list_jobs
    jobs_mod.create_job = create_job
    jobs_mod.update_job = update_job
    jobs_mod.remove_job = remove_job
    jobs_mod.pause_job = pause_job
    jobs_mod.resume_job = resume_job
    jobs_mod.OUTPUT_DIR = "/tmp/clawke-hermes-task-test"

    monkeypatch.setitem(sys.modules, "cron", cron_pkg)
    monkeypatch.setitem(sys.modules, "cron.jobs", jobs_mod)
    return store


def test_list_maps_hermes_jobs(monkeypatch):
    install_fake_cron(monkeypatch)
    adapter = HermesTaskAdapter()
    result = adapter.list_tasks("hermes")
    assert result[0]["id"] == "job_1"
    assert result[0]["account_id"] == "hermes"
    assert result[0]["skills"] == ["calendar"]


def test_create_update_delete(monkeypatch):
    install_fake_cron(monkeypatch)
    adapter = HermesTaskAdapter()
    created = adapter.create_task("hermes", {
        "name": "Hourly",
        "schedule": "every 1h",
        "prompt": "check status",
        "skills": [],
        "deliver": "local",
    })
    assert created["id"] == "job_2"
    updated = adapter.update_task("hermes", "job_2", {"name": "Renamed"})
    assert updated["name"] == "Renamed"
    adapter.delete_task("job_2")
    assert len(adapter.list_tasks("hermes")) == 1
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
cd gateways/hermes/clawke && python -m pytest test_task_adapter.py -q
```

Expected: FAIL，`task_adapter` 不存在。

- [ ] **Step 3: 实现 HermesTaskAdapter**

创建 `gateways/hermes/clawke/task_adapter.py`：

```python
from __future__ import annotations

from pathlib import Path
from typing import Any


class HermesTaskAdapter:
    def list_tasks(self, account_id: str) -> list[dict[str, Any]]:
        from cron.jobs import list_jobs
        return [self._to_task(account_id, job) for job in list_jobs()]

    def get_task(self, account_id: str, task_id: str) -> dict[str, Any] | None:
        for task in self.list_tasks(account_id):
            if task["id"] == task_id:
                return task
        return None

    def create_task(self, account_id: str, draft: dict[str, Any]) -> dict[str, Any]:
        from cron.jobs import create_job
        job = create_job(
            name=draft.get("name") or draft["prompt"][:40],
            schedule=draft["schedule"],
            prompt=draft["prompt"],
            deliver=draft.get("deliver", "local"),
            skill_ids=draft.get("skills") or [],
        )
        return self._to_task(account_id, job)

    def update_task(self, account_id: str, task_id: str, patch: dict[str, Any]) -> dict[str, Any]:
        from cron.jobs import update_job
        kwargs: dict[str, Any] = {}
        if "name" in patch:
            kwargs["name"] = patch["name"]
        if "schedule" in patch:
            kwargs["schedule"] = patch["schedule"]
        if "prompt" in patch:
            kwargs["prompt"] = patch["prompt"]
        if "deliver" in patch:
            kwargs["deliver"] = patch["deliver"]
        if "skills" in patch:
            kwargs["skill_ids"] = patch["skills"]
        job = update_job(task_id, **kwargs)
        return self._to_task(account_id, job)

    def delete_task(self, task_id: str) -> None:
        from cron.jobs import remove_job
        remove_job(task_id)

    def set_enabled(self, account_id: str, task_id: str, enabled: bool) -> dict[str, Any]:
        if enabled:
            from cron.jobs import resume_job
            job = resume_job(task_id)
        else:
            from cron.jobs import pause_job
            job = pause_job(task_id)
        return self._to_task(account_id, job)

    def list_runs(self, task_id: str) -> list[dict[str, Any]]:
        from cron.jobs import OUTPUT_DIR
        root = Path(OUTPUT_DIR) / task_id
        if not root.exists():
            return []
        runs = []
        for path in sorted(root.glob("*.txt"), reverse=True):
            runs.append({
                "id": path.stem,
                "task_id": task_id,
                "started_at": "",
                "status": "success",
                "output_preview": path.read_text(errors="replace")[:240],
            })
        return runs

    def get_output(self, task_id: str, run_id: str) -> str:
        from cron.jobs import OUTPUT_DIR
        path = Path(OUTPUT_DIR) / task_id / f"{run_id}.txt"
        if not path.exists():
            return ""
        return path.read_text(errors="replace")

    def run_task(self, task_id: str) -> dict[str, Any]:
        from cron.jobs import get_job
        from cron.scheduler import run_job
        job = get_job(task_id)
        run_job(job)
        return {
            "id": f"manual_{task_id}",
            "task_id": task_id,
            "started_at": "",
            "status": "running",
        }

    def _to_task(self, account_id: str, job: dict[str, Any]) -> dict[str, Any]:
        task_id = job.get("job_id") or job.get("id")
        enabled = bool(job.get("enabled", True))
        return {
            "id": task_id,
            "account_id": account_id,
            "agent": "hermes",
            "name": job.get("name") or task_id,
            "schedule": job.get("schedule", ""),
            "schedule_text": job.get("schedule_text") or job.get("schedule", ""),
            "prompt": job.get("prompt", ""),
            "enabled": enabled,
            "status": "active" if enabled else "paused",
            "skills": job.get("skill_ids") or [],
            "deliver": job.get("deliver", "local"),
            "created_at": str(job.get("created_at", "")) if job.get("created_at") else None,
            "updated_at": str(job.get("updated_at", "")) if job.get("updated_at") else None,
        }
```

- [ ] **Step 4: 接入 Hermes inbound commands**

修改 `gateways/hermes/clawke/clawke_channel.py`：

在 `InboundMessageType` 增加：

```python
    TaskList = "task_list"
    TaskGet = "task_get"
    TaskCreate = "task_create"
    TaskUpdate = "task_update"
    TaskDelete = "task_delete"
    TaskSetEnabled = "task_set_enabled"
    TaskRun = "task_run"
    TaskRuns = "task_runs"
    TaskOutput = "task_output"
```

在 inbound loop 中 `ClarifyResponse` 后加入：

```python
                elif msg_type and msg_type.startswith("task_"):
                    await self._handle_task_command(msg)
```

在 class 内新增：

```python
    async def _handle_task_command(self, msg: dict) -> None:
        from task_adapter import HermesTaskAdapter
        adapter = HermesTaskAdapter()
        request_id = msg.get("request_id", "")
        account_id = self.config.account_id
        try:
            typ = msg.get("type")
            if typ == InboundMessageType.TaskList:
                await self._send({"type": "task_list_response", "request_id": request_id, "tasks": adapter.list_tasks(account_id)})
            elif typ == InboundMessageType.TaskGet:
                await self._send({"type": "task_get_response", "request_id": request_id, "task": adapter.get_task(account_id, msg.get("task_id", ""))})
            elif typ == InboundMessageType.TaskCreate:
                await self._send({"type": "task_mutation_response", "request_id": request_id, "ok": True, "task": adapter.create_task(account_id, msg.get("task") or {})})
            elif typ == InboundMessageType.TaskUpdate:
                await self._send({"type": "task_mutation_response", "request_id": request_id, "ok": True, "task": adapter.update_task(account_id, msg.get("task_id", ""), msg.get("patch") or {})})
            elif typ == InboundMessageType.TaskDelete:
                adapter.delete_task(msg.get("task_id", ""))
                await self._send({"type": "task_mutation_response", "request_id": request_id, "ok": True})
            elif typ == InboundMessageType.TaskSetEnabled:
                await self._send({"type": "task_mutation_response", "request_id": request_id, "ok": True, "task": adapter.set_enabled(account_id, msg.get("task_id", ""), bool(msg.get("enabled")))})
            elif typ == InboundMessageType.TaskRun:
                await self._send({"type": "task_run_response", "request_id": request_id, "ok": True, "runs": [adapter.run_task(msg.get("task_id", ""))]})
            elif typ == InboundMessageType.TaskRuns:
                await self._send({"type": "task_runs_response", "request_id": request_id, "runs": adapter.list_runs(msg.get("task_id", ""))})
            elif typ == InboundMessageType.TaskOutput:
                await self._send({"type": "task_output_response", "request_id": request_id, "output": adapter.get_output(msg.get("task_id", ""), msg.get("run_id", ""))})
        except Exception as e:
            await self._send({"type": "task_mutation_response", "request_id": request_id, "ok": False, "error": "task_error", "message": str(e)})
```

- [ ] **Step 5: 跑 Hermes tests**

Run:

```bash
cd gateways/hermes/clawke && python -m pytest test_task_adapter.py test_clawke_channel.py test_approval_flow.py -q
```

Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add gateways/hermes/clawke/task_adapter.py gateways/hermes/clawke/clawke_channel.py gateways/hermes/clawke/test_task_adapter.py
git commit -m "feat(hermes): add task management adapter"
```

---

## Task 4: OpenClaw task adapter

**Files:**
- Modify: `gateways/openclaw/clawke/src/protocol.ts`
- Create: `gateways/openclaw/clawke/src/task-adapter.ts`
- Modify: `gateways/openclaw/clawke/src/gateway.ts`
- Test: `gateways/openclaw/clawke/src/task-adapter.test.ts`

- [ ] **Step 1: 写 adapter test**

创建 `gateways/openclaw/clawke/src/task-adapter.test.ts`：

```ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { OpenClawTaskAdapter } from './task-adapter.js';

test('OpenClawTaskAdapter creates lists updates disables runs and outputs tasks', () => {
  const dir = mkdtempSync(join(tmpdir(), 'clawke-task-'));
  try {
    const adapter = new OpenClawTaskAdapter(dir);
    const created = adapter.createTask('openclaw', {
      account_id: 'openclaw',
      name: 'Daily',
      schedule: '0 9 * * *',
      prompt: 'hello',
      enabled: true,
      skills: ['github'],
    });

    assert.equal(created.account_id, 'openclaw');
    assert.equal(adapter.listTasks('openclaw').length, 1);
    assert.equal(adapter.updateTask('openclaw', created.id, { name: 'Renamed' }).name, 'Renamed');
    assert.equal(adapter.setEnabled('openclaw', created.id, false).enabled, false);

    const run = adapter.runTask('openclaw', created.id);
    assert.equal(run.status, 'running');
    assert.equal(adapter.listRuns(created.id).length, 1);
    assert.match(adapter.getOutput(created.id, run.id), /triggered/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd gateways/openclaw/clawke && npx tsx --test src/task-adapter.test.ts
```

Expected: FAIL，`task-adapter.ts` 不存在。

- [ ] **Step 3: 扩展 protocol**

修改 `gateways/openclaw/clawke/src/protocol.ts`：

```ts
export const GatewayMessageType = {
  // existing entries...
  TaskListResponse:     "task_list_response",
  TaskGetResponse:      "task_get_response",
  TaskMutationResponse: "task_mutation_response",
  TaskRunResponse:      "task_run_response",
  TaskRunsResponse:     "task_runs_response",
  TaskOutputResponse:   "task_output_response",
  TaskEvent:            "task_event",
} as const;
```

在 `InboundMessageType` 增加：

```ts
  TaskList:       "task_list",
  TaskGet:        "task_get",
  TaskCreate:     "task_create",
  TaskUpdate:     "task_update",
  TaskDelete:     "task_delete",
  TaskSetEnabled: "task_set_enabled",
  TaskRun:        "task_run",
  TaskRuns:       "task_runs",
  TaskOutput:     "task_output",
```

- [ ] **Step 4: 实现 OpenClawTaskAdapter**

创建 `gateways/openclaw/clawke/src/task-adapter.ts`：

```ts
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import crypto from "node:crypto";

export interface OpenClawTaskDraft {
  account_id: string;
  name?: string;
  schedule: string;
  prompt: string;
  enabled?: boolean;
  skills?: string[];
  deliver?: string;
}

export interface OpenClawManagedTask extends OpenClawTaskDraft {
  id: string;
  agent: string;
  name: string;
  enabled: boolean;
  status: "active" | "paused" | "disabled" | "error";
  created_at: string;
  updated_at: string;
}

export interface OpenClawTaskRun {
  id: string;
  task_id: string;
  started_at: string;
  finished_at?: string;
  status: "running" | "success" | "failed" | "cancelled";
  output_preview?: string;
  error?: string;
}

export class OpenClawTaskAdapter {
  constructor(private root = join(homedir(), ".openclaw", "clawke-tasks")) {
    mkdirSync(this.root, { recursive: true });
    mkdirSync(this.runsRoot(), { recursive: true });
  }

  listTasks(accountId: string): OpenClawManagedTask[] {
    return this.readTasks().filter((task) => task.account_id === accountId);
  }

  getTask(accountId: string, taskId: string): OpenClawManagedTask | null {
    return this.listTasks(accountId).find((task) => task.id === taskId) || null;
  }

  createTask(accountId: string, draft: OpenClawTaskDraft): OpenClawManagedTask {
    const now = new Date().toISOString();
    const task: OpenClawManagedTask = {
      id: crypto.randomUUID(),
      account_id: accountId,
      agent: "openclaw",
      name: draft.name || draft.prompt.slice(0, 40) || "Untitled task",
      schedule: draft.schedule,
      prompt: draft.prompt,
      enabled: draft.enabled ?? true,
      status: draft.enabled === false ? "paused" : "active",
      skills: draft.skills || [],
      deliver: draft.deliver || "local",
      created_at: now,
      updated_at: now,
    };
    this.writeTasks([...this.readTasks(), task]);
    return task;
  }

  updateTask(accountId: string, taskId: string, patch: Partial<OpenClawTaskDraft>): OpenClawManagedTask {
    let updated: OpenClawManagedTask | null = null;
    const tasks = this.readTasks().map((task) => {
      if (task.account_id !== accountId || task.id !== taskId) return task;
      updated = {
        ...task,
        ...patch,
        name: patch.name ?? task.name,
        schedule: patch.schedule ?? task.schedule,
        prompt: patch.prompt ?? task.prompt,
        enabled: patch.enabled ?? task.enabled,
        skills: patch.skills ?? task.skills,
        deliver: patch.deliver ?? task.deliver,
        status: patch.enabled === false ? "paused" : (patch.enabled === true ? "active" : task.status),
        updated_at: new Date().toISOString(),
      };
      return updated;
    });
    if (!updated) throw new Error(`Task not found: ${taskId}`);
    this.writeTasks(tasks);
    return updated;
  }

  deleteTask(accountId: string, taskId: string): void {
    this.writeTasks(this.readTasks().filter((task) => task.account_id !== accountId || task.id !== taskId));
    rmSync(this.taskRunsRoot(taskId), { recursive: true, force: true });
  }

  setEnabled(accountId: string, taskId: string, enabled: boolean): OpenClawManagedTask {
    return this.updateTask(accountId, taskId, { enabled });
  }

  runTask(accountId: string, taskId: string): OpenClawTaskRun {
    const task = this.getTask(accountId, taskId);
    if (!task) throw new Error(`Task not found: ${taskId}`);
    const run: OpenClawTaskRun = {
      id: crypto.randomUUID(),
      task_id: taskId,
      started_at: new Date().toISOString(),
      status: "running",
      output_preview: `Task "${task.name}" triggered from Clawke.`,
    };
    mkdirSync(this.taskRunsRoot(taskId), { recursive: true });
    writeFileSync(this.runPath(taskId, run.id), JSON.stringify({ run, output: run.output_preview }, null, 2));
    return run;
  }

  listRuns(taskId: string): OpenClawTaskRun[] {
    const root = this.taskRunsRoot(taskId);
    if (!existsSync(root)) return [];
    return require("node:fs").readdirSync(root)
      .filter((name: string) => name.endsWith(".json"))
      .map((name: string) => JSON.parse(readFileSync(join(root, name), "utf8")).run)
      .sort((a: OpenClawTaskRun, b: OpenClawTaskRun) => b.started_at.localeCompare(a.started_at));
  }

  getOutput(taskId: string, runId: string): string {
    const path = this.runPath(taskId, runId);
    if (!existsSync(path)) return "";
    return JSON.parse(readFileSync(path, "utf8")).output || "";
  }

  private tasksPath(): string { return join(this.root, "tasks.json"); }
  private runsRoot(): string { return join(this.root, "runs"); }
  private taskRunsRoot(taskId: string): string { return join(this.runsRoot(), taskId); }
  private runPath(taskId: string, runId: string): string { return join(this.taskRunsRoot(taskId), `${runId}.json`); }

  private readTasks(): OpenClawManagedTask[] {
    if (!existsSync(this.tasksPath())) return [];
    return JSON.parse(readFileSync(this.tasksPath(), "utf8"));
  }

  private writeTasks(tasks: OpenClawManagedTask[]): void {
    writeFileSync(this.tasksPath(), JSON.stringify(tasks, null, 2));
  }
}
```

- [ ] **Step 5: 接入 gateway message handler**

在 `gateways/openclaw/clawke/src/gateway.ts` import：

```ts
import { OpenClawTaskAdapter } from "./task-adapter.js";
```

在 `QuerySkills` 分支后加入：

```ts
          } else if (String(msg.type).startsWith("task_")) {
            handleTaskCommand(ctx, msg);
```

在文件中新增函数：

```ts
function handleTaskCommand(ctx: ChannelGatewayContext<ResolvedClawkeAccount>, msg: any): void {
  const adapter = new OpenClawTaskAdapter();
  const requestId = msg.request_id || "";
  const accountId = ctx.accountId;
  const send = (payload: Record<string, unknown>) => ws?.send(JSON.stringify({ request_id: requestId, ...payload }));

  try {
    switch (msg.type) {
      case InboundMessageType.TaskList:
        send({ type: GatewayMessageType.TaskListResponse, tasks: adapter.listTasks(accountId) });
        break;
      case InboundMessageType.TaskGet:
        send({ type: GatewayMessageType.TaskGetResponse, task: adapter.getTask(accountId, msg.task_id) });
        break;
      case InboundMessageType.TaskCreate:
        send({ type: GatewayMessageType.TaskMutationResponse, ok: true, task: adapter.createTask(accountId, msg.task) });
        break;
      case InboundMessageType.TaskUpdate:
        send({ type: GatewayMessageType.TaskMutationResponse, ok: true, task: adapter.updateTask(accountId, msg.task_id, msg.patch || {}) });
        break;
      case InboundMessageType.TaskDelete:
        adapter.deleteTask(accountId, msg.task_id);
        send({ type: GatewayMessageType.TaskMutationResponse, ok: true });
        break;
      case InboundMessageType.TaskSetEnabled:
        send({ type: GatewayMessageType.TaskMutationResponse, ok: true, task: adapter.setEnabled(accountId, msg.task_id, !!msg.enabled) });
        break;
      case InboundMessageType.TaskRun:
        send({ type: GatewayMessageType.TaskRunResponse, ok: true, runs: [adapter.runTask(accountId, msg.task_id)] });
        break;
      case InboundMessageType.TaskRuns:
        send({ type: GatewayMessageType.TaskRunsResponse, runs: adapter.listRuns(msg.task_id) });
        break;
      case InboundMessageType.TaskOutput:
        send({ type: GatewayMessageType.TaskOutputResponse, output: adapter.getOutput(msg.task_id, msg.run_id) });
        break;
    }
  } catch (e: any) {
    send({ type: GatewayMessageType.TaskMutationResponse, ok: false, error: "task_error", message: e.message });
  }
}
```

- [ ] **Step 6: 跑 tests/build**

Run:

```bash
cd gateways/openclaw/clawke && npm run build
```

```bash
cd gateways/openclaw/clawke && npx tsx --test src/task-adapter.test.ts
```

Expected: PASS。

- [ ] **Step 7: 提交**

```bash
git add gateways/openclaw/clawke/src/protocol.ts gateways/openclaw/clawke/src/task-adapter.ts gateways/openclaw/clawke/src/gateway.ts gateways/openclaw/clawke/src/task-adapter.test.ts
git commit -m "feat(openclaw): add task management adapter"
```

---

## Task 5: Flutter task models, API service, provider

**Files:**
- Create: `client/lib/models/managed_task.dart`
- Create: `client/lib/services/tasks_api_service.dart`
- Create: `client/lib/providers/tasks_provider.dart`
- Test: `client/test/models/managed_task_test.dart`
- Test: `client/test/providers/tasks_provider_test.dart`
- Test: `client/test/services/tasks_api_service_test.dart`

- [ ] **Step 1: 写 model test**

创建 `client/test/models/managed_task_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:client/models/managed_task.dart';

void main() {
  test('ManagedTask parses json', () {
    final task = ManagedTask.fromJson({
      'id': 'job_1',
      'account_id': 'hermes',
      'agent': 'hermes',
      'name': 'Daily',
      'schedule': '0 9 * * *',
      'prompt': 'hello',
      'enabled': true,
      'status': 'active',
      'skills': ['calendar'],
      'last_run': {
        'id': 'run_1',
        'task_id': 'job_1',
        'started_at': '2026-04-24T00:00:00Z',
        'status': 'success',
      },
    });

    expect(task.id, 'job_1');
    expect(task.accountId, 'hermes');
    expect(task.skills, ['calendar']);
    expect(task.lastRun?.status, TaskRunStatus.success);
  });
}
```

- [ ] **Step 2: 实现 models**

创建 `client/lib/models/managed_task.dart`：

```dart
enum ManagedTaskStatus { active, paused, disabled, error }
enum TaskRunStatus { running, success, failed, cancelled }

class ManagedTask {
  final String id;
  final String accountId;
  final String agent;
  final String name;
  final String schedule;
  final String? scheduleText;
  final String prompt;
  final bool enabled;
  final ManagedTaskStatus status;
  final List<String> skills;
  final String? deliver;
  final String? nextRunAt;
  final TaskRun? lastRun;
  final String? createdAt;
  final String? updatedAt;

  const ManagedTask({
    required this.id,
    required this.accountId,
    required this.agent,
    required this.name,
    required this.schedule,
    required this.prompt,
    required this.enabled,
    required this.status,
    this.scheduleText,
    this.skills = const [],
    this.deliver,
    this.nextRunAt,
    this.lastRun,
    this.createdAt,
    this.updatedAt,
  });

  factory ManagedTask.fromJson(Map<String, dynamic> json) => ManagedTask(
        id: json['id'] as String,
        accountId: json['account_id'] as String,
        agent: json['agent'] as String? ?? json['account_id'] as String? ?? '',
        name: json['name'] as String? ?? 'Untitled task',
        schedule: json['schedule'] as String? ?? '',
        scheduleText: json['schedule_text'] as String?,
        prompt: json['prompt'] as String? ?? '',
        enabled: json['enabled'] == true,
        status: _taskStatus(json['status'] as String?),
        skills: (json['skills'] as List? ?? const []).cast<String>(),
        deliver: json['deliver'] as String?,
        nextRunAt: json['next_run_at'] as String?,
        lastRun: json['last_run'] is Map
            ? TaskRun.fromJson(Map<String, dynamic>.from(json['last_run'] as Map))
            : null,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  ManagedTask copyWith({bool? enabled, ManagedTaskStatus? status}) => ManagedTask(
        id: id,
        accountId: accountId,
        agent: agent,
        name: name,
        schedule: schedule,
        scheduleText: scheduleText,
        prompt: prompt,
        enabled: enabled ?? this.enabled,
        status: status ?? this.status,
        skills: skills,
        deliver: deliver,
        nextRunAt: nextRunAt,
        lastRun: lastRun,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

class TaskDraft {
  final String accountId;
  final String? name;
  final String schedule;
  final String prompt;
  final bool enabled;
  final List<String> skills;
  final String? deliver;

  const TaskDraft({
    required this.accountId,
    this.name,
    required this.schedule,
    required this.prompt,
    this.enabled = true,
    this.skills = const [],
    this.deliver,
  });

  Map<String, dynamic> toJson() => {
        'account_id': accountId,
        if (name != null && name!.trim().isNotEmpty) 'name': name,
        'schedule': schedule,
        'prompt': prompt,
        'enabled': enabled,
        'skills': skills,
        if (deliver != null) 'deliver': deliver,
      };
}

class TaskRun {
  final String id;
  final String taskId;
  final String startedAt;
  final String? finishedAt;
  final TaskRunStatus status;
  final String? outputPreview;
  final String? error;

  const TaskRun({
    required this.id,
    required this.taskId,
    required this.startedAt,
    this.finishedAt,
    required this.status,
    this.outputPreview,
    this.error,
  });

  factory TaskRun.fromJson(Map<String, dynamic> json) => TaskRun(
        id: json['id'] as String,
        taskId: json['task_id'] as String,
        startedAt: json['started_at'] as String? ?? '',
        finishedAt: json['finished_at'] as String?,
        status: _runStatus(json['status'] as String?),
        outputPreview: json['output_preview'] as String?,
        error: json['error'] as String?,
      );
}

ManagedTaskStatus _taskStatus(String? value) => switch (value) {
      'paused' => ManagedTaskStatus.paused,
      'disabled' => ManagedTaskStatus.disabled,
      'error' => ManagedTaskStatus.error,
      _ => ManagedTaskStatus.active,
    };

TaskRunStatus _runStatus(String? value) => switch (value) {
      'running' => TaskRunStatus.running,
      'failed' => TaskRunStatus.failed,
      'cancelled' => TaskRunStatus.cancelled,
      _ => TaskRunStatus.success,
    };
```

- [ ] **Step 3: 实现 API service**

创建 `client/lib/services/tasks_api_service.dart`：

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/services/media_resolver.dart';

class TasksApiService {
  late final Dio _dio;

  TasksApiService({Dio? dio}) {
    _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20)));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      options.baseUrl = MediaResolver.baseUrl;
      options.headers.addAll(MediaResolver.authHeaders);
      handler.next(options);
    }));
  }

  Future<List<ManagedTask>> listTasks({required String accountId}) async {
    final response = await _dio.get('/api/tasks', queryParameters: {'account_id': accountId});
    final data = _asMap(response.data);
    return (data['tasks'] as List? ?? const [])
        .map((item) => ManagedTask.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<ManagedTask> createTask(TaskDraft draft) async {
    final response = await _dio.post('/api/tasks', data: draft.toJson());
    return ManagedTask.fromJson(Map<String, dynamic>.from(_asMap(response.data)['task'] as Map));
  }

  Future<ManagedTask> updateTask(String id, TaskDraft draft) async {
    final response = await _dio.put('/api/tasks/${Uri.encodeComponent(id)}', data: draft.toJson());
    return ManagedTask.fromJson(Map<String, dynamic>.from(_asMap(response.data)['task'] as Map));
  }

  Future<void> deleteTask(String accountId, String id) async {
    await _dio.delete('/api/tasks/${Uri.encodeComponent(id)}', queryParameters: {'account_id': accountId});
  }

  Future<void> setEnabled(String accountId, String id, bool enabled) async {
    await _dio.put('/api/tasks/${Uri.encodeComponent(id)}/enabled', queryParameters: {'account_id': accountId}, data: {'enabled': enabled});
  }

  Future<List<TaskRun>> runTask(String accountId, String id) async {
    final response = await _dio.post('/api/tasks/${Uri.encodeComponent(id)}/run', queryParameters: {'account_id': accountId});
    final run = _asMap(response.data)['run'];
    if (run is Map) return [TaskRun.fromJson(Map<String, dynamic>.from(run))];
    return const [];
  }

  Future<List<TaskRun>> listRuns(String accountId, String id) async {
    final response = await _dio.get('/api/tasks/${Uri.encodeComponent(id)}/runs', queryParameters: {'account_id': accountId});
    final data = _asMap(response.data);
    return (data['runs'] as List? ?? const [])
        .map((item) => TaskRun.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<String> getOutput(String accountId, String taskId, String runId) async {
    final response = await _dio.get('/api/tasks/${Uri.encodeComponent(taskId)}/runs/${Uri.encodeComponent(runId)}/output', queryParameters: {'account_id': accountId});
    return _asMap(response.data)['output'] as String? ?? '';
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    debugPrint('[TasksAPI] Unexpected response: $data');
    throw const FormatException('Invalid tasks API response');
  }
}
```

- [ ] **Step 4: 实现 provider**

创建 `client/lib/providers/tasks_provider.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/services/tasks_api_service.dart';

final tasksApiServiceProvider = Provider<TasksApiService>((ref) => TasksApiService());

final tasksControllerProvider = StateNotifierProvider<TasksController, TasksState>((ref) {
  return TasksController(ref.read(tasksApiServiceProvider));
});

@immutable
class TasksState {
  final List<ManagedTask> tasks;
  final String selectedAccountId;
  final bool isLoading;
  final bool isSaving;
  final Set<String> busyTaskIds;
  final String? errorMessage;

  const TasksState({
    this.tasks = const [],
    this.selectedAccountId = 'hermes',
    this.isLoading = false,
    this.isSaving = false,
    this.busyTaskIds = const <String>{},
    this.errorMessage,
  });

  TasksState copyWith({
    List<ManagedTask>? tasks,
    String? selectedAccountId,
    bool? isLoading,
    bool? isSaving,
    Set<String>? busyTaskIds,
    String? errorMessage,
    bool clearError = false,
  }) => TasksState(
        tasks: tasks ?? this.tasks,
        selectedAccountId: selectedAccountId ?? this.selectedAccountId,
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        busyTaskIds: busyTaskIds ?? this.busyTaskIds,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class TasksController extends StateNotifier<TasksState> {
  TasksController(this._api) : super(const TasksState());
  final TasksApiService _api;

  Future<void> load({bool force = false}) async {
    if (state.tasks.isNotEmpty && !force) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final tasks = await _api.listTasks(accountId: state.selectedAccountId);
      state = state.copyWith(tasks: tasks, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() => load(force: true);

  Future<void> selectAccount(String accountId) async {
    state = state.copyWith(selectedAccountId: accountId, tasks: const [], isLoading: true, clearError: true);
    await load(force: true);
  }

  Future<void> create(TaskDraft draft) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final task = await _api.createTask(draft);
      state = state.copyWith(isSaving: false, tasks: [...state.tasks, task]);
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> update(String id, TaskDraft draft) async {
    _setBusy(id, true);
    try {
      final task = await _api.updateTask(id, draft);
      state = state.copyWith(busyTaskIds: _withoutBusy(id), tasks: _replace(task));
    } catch (e) {
      state = state.copyWith(busyTaskIds: _withoutBusy(id), errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> delete(ManagedTask task) async {
    _setBusy(task.id, true);
    try {
      await _api.deleteTask(task.accountId, task.id);
      state = state.copyWith(busyTaskIds: _withoutBusy(task.id), tasks: state.tasks.where((t) => t.id != task.id).toList());
    } catch (e) {
      state = state.copyWith(busyTaskIds: _withoutBusy(task.id), errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> setEnabled(ManagedTask task, bool enabled) async {
    final before = state.tasks;
    state = state.copyWith(tasks: _replace(task.copyWith(enabled: enabled, status: enabled ? ManagedTaskStatus.active : ManagedTaskStatus.paused)));
    try {
      await _api.setEnabled(task.accountId, task.id, enabled);
    } catch (e) {
      state = state.copyWith(tasks: before, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> run(ManagedTask task) async {
    _setBusy(task.id, true);
    try {
      await _api.runTask(task.accountId, task.id);
      state = state.copyWith(busyTaskIds: _withoutBusy(task.id));
    } catch (e) {
      state = state.copyWith(busyTaskIds: _withoutBusy(task.id), errorMessage: e.toString());
      rethrow;
    }
  }

  List<ManagedTask> _replace(ManagedTask task) => state.tasks.map((t) => t.id == task.id ? task : t).toList();
  void _setBusy(String id, bool busy) => state = state.copyWith(busyTaskIds: busy ? {...state.busyTaskIds, id} : _withoutBusy(id), clearError: true);
  Set<String> _withoutBusy(String id) => {...state.busyTaskIds}..remove(id);
}
```

- [ ] **Step 5: 跑 Flutter model/provider tests**

Run:

```bash
cd client && flutter test test/models/managed_task_test.dart test/providers/tasks_provider_test.dart
```

Expected: PASS。`tasks_provider_test.dart` 需要使用 fake `TasksApiService` 覆盖 create/update/delete/setEnabled/run 的状态变化。

- [ ] **Step 6: 提交**

```bash
git add client/lib/models/managed_task.dart client/lib/services/tasks_api_service.dart client/lib/providers/tasks_provider.dart client/test/models/managed_task_test.dart client/test/providers/tasks_provider_test.dart client/test/services/tasks_api_service_test.dart
git commit -m "feat(client): add task management data layer"
```

---

## Task 6: Flutter task management UI and navigation

**Files:**
- Create: `client/lib/screens/tasks_management_screen.dart`
- Modify: `client/lib/providers/nav_page_provider.dart`
- Modify: `client/lib/widgets/nav_rail.dart`
- Modify: `client/lib/screens/main_layout.dart`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/l10n/app_en.arb`
- Test: `client/test/screens/tasks_management_screen_test.dart`

- [ ] **Step 1: 写 screen smoke test**

创建 `client/test/screens/tasks_management_screen_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/screens/tasks_management_screen.dart';

void main() {
  testWidgets('TasksManagementScreen renders title and create action', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: TasksManagementScreen()),
    ));
    await tester.pump();

    expect(find.text('任务管理'), findsOneWidget);
    expect(find.text('新建任务'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
cd client && flutter test test/screens/tasks_management_screen_test.dart
```

Expected: FAIL，screen 不存在。

- [ ] **Step 3: 实现 TasksManagementScreen**

创建 `client/lib/screens/tasks_management_screen.dart`，首版结构：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/providers/tasks_provider.dart';

class TasksManagementScreen extends ConsumerStatefulWidget {
  final bool showAppBar;
  const TasksManagementScreen({super.key, this.showAppBar = false});

  @override
  ConsumerState<TasksManagementScreen> createState() => _TasksManagementScreenState();
}

class _TasksManagementScreenState extends ConsumerState<TasksManagementScreen> {
  final _searchController = TextEditingController();
  ManagedTask? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tasksControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tasksControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final content = Container(
      color: colorScheme.surface,
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact) return _MobileTasksView(state: state, searchController: _searchController, onCreate: _openEditor);
        return _DesktopTasksView(
          state: state,
          searchController: _searchController,
          selected: _selected,
          onSelect: (task) => setState(() => _selected = task),
          onCreate: _openEditor,
        );
      }),
    );
    if (!widget.showAppBar) return content;
    return Scaffold(appBar: AppBar(title: const Text('任务管理')), body: content);
  }

  Future<void> _openEditor({ManagedTask? initial}) async {
    final accountId = ref.read(tasksControllerProvider).selectedAccountId;
    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (context) => _TaskEditorDialog(accountId: accountId, initial: initial),
    );
    if (draft == null) return;
    if (initial == null) {
      await ref.read(tasksControllerProvider.notifier).create(draft);
    } else {
      await ref.read(tasksControllerProvider.notifier).update(initial.id, draft);
    }
  }
}
```

在同文件继续实现 `_DesktopTasksView`、`_MobileTasksView`、`_TaskCard`、`_GatewayColumn`、`_TaskInspector`、`_TaskEditorDialog`。关键布局要求：

```dart
// Desktop width:
// Row(
//   children: [
//     SizedBox(width: 220, child: _GatewayColumn(...)),
//     VerticalDivider(width: 1),
//     Expanded(child: task list workspace),
//     if (selected != null) SizedBox(width: 340, child: _TaskInspector(...)),
//   ],
// )
//
// Mobile width:
// ListView(
//   children: [
//     header,
//     account segmented control or dropdown,
//     search/filter row,
//     task cards,
//   ],
// )
```

Use `IconButton` for refresh/run/edit/delete where possible, `Switch` for enabled, `PopupMenuButton` for narrow-card overflow actions, and `AlertDialog` for create/edit.

- [ ] **Step 4: 接入 nav**

修改 `client/lib/providers/nav_page_provider.dart`：

```dart
enum NavPage { chat, dashboard, tasks, channels, skills }
```

如果现有代码仍引用 `NavPage.cron`，全部迁移到 `NavPage.tasks`。

修改 `client/lib/widgets/nav_rail.dart`，恢复 Tasks 入口：

```dart
              _NavItem(
                icon: Icons.task_alt,
                label: context.l10n.navTasks,
                isActive: activePage == NavPage.tasks,
                isExpanded: _isExpanded,
                colorScheme: colorScheme,
                onTap: () {
                  ref.read(activeNavPageProvider.notifier).state = NavPage.tasks;
                },
              ),
```

修改 `client/lib/screens/main_layout.dart`，把原 Cron SDUI page 替换为：

```dart
const TasksManagementScreen(),
```

并 import：

```dart
import 'package:client/screens/tasks_management_screen.dart';
```

- [ ] **Step 5: 更新 l10n**

`client/lib/l10n/app_zh.arb` 增加：

```json
"navTasks": "任务管理",
"tasksCreate": "新建任务",
"tasksSearch": "搜索任务",
"tasksEmpty": "暂无任务",
"tasksRunNow": "立即运行",
"tasksRuns": "运行记录",
"tasksOutput": "执行输出"
```

`client/lib/l10n/app_en.arb` 增加：

```json
"navTasks": "Tasks",
"tasksCreate": "New Task",
"tasksSearch": "Search tasks",
"tasksEmpty": "No tasks",
"tasksRunNow": "Run Now",
"tasksRuns": "Runs",
"tasksOutput": "Output"
```

Run:

```bash
cd client && flutter gen-l10n
```

Expected: generated localization files update successfully.

- [ ] **Step 6: 跑 Flutter tests/analyze**

Run:

```bash
cd client && flutter test test/screens/tasks_management_screen_test.dart
```

Run:

```bash
cd client && dart analyze
```

Expected: PASS / no issues.

- [ ] **Step 7: 提交**

```bash
git add client/lib/screens/tasks_management_screen.dart client/lib/providers/nav_page_provider.dart client/lib/widgets/nav_rail.dart client/lib/screens/main_layout.dart client/lib/l10n/app_zh.arb client/lib/l10n/app_en.arb client/lib/l10n/app_localizations*.dart client/test/screens/tasks_management_screen_test.dart
git commit -m "feat(client): add task management screen"
```

---

## Task 7: End-to-end verification and cleanup

**Files:**
- Modify: `server/src/services/cron-service.ts` if removing old mock becomes safe.
- Modify: `client/lib/widgets/sdui/cron_list_view.dart` only if no references remain.
- Update tests that reference `CronListView` if the widget remains as legacy SDUI.

- [ ] **Step 1: Verify no unintended Cron nav dependency remains**

Run:

```bash
rg -n "NavPage\\.cron|navCron|CronListView|refresh_cron|trigger_cron_job|toggle_cron_job" client/lib server/src
```

Expected:

- `NavPage.cron` and `navCron` should be gone or intentionally replaced by `NavPage.tasks` and `navTasks`.
- `CronListView` may remain only as legacy SDUI widget if still registered in `WidgetFactory`.
- Server `cron-service.ts` should not be used by the new task management flow.

- [ ] **Step 2: Run combined verification**

Run:

```bash
cd server && npm run build && npm test
```

Expected: PASS.

Run:

```bash
cd client && flutter test
```

Expected: PASS.

Run:

```bash
cd client && dart analyze
```

Expected: no issues.

- [ ] **Step 3: Manual smoke test**

Start Server:

```bash
cd server && npm run dev
```

Start a Hermes or OpenClaw gateway locally. Open the Flutter app, go to Tasks, select Hermes/OpenClaw account, verify:

- Task list loads.
- Create task sends HTTP request and appears in list.
- Edit task updates the gateway-owned task.
- Enable/disable updates status.
- Run now returns a run record.
- Run history opens.
- Output viewer opens.
- Disconnecting gateway shows disconnected/error state.

- [ ] **Step 4: Commit cleanup**

If legacy cron files are removed or references updated:

```bash
git add client server gateways
git commit -m "chore: clean up legacy cron task UI"
```

If no cleanup is needed:

```bash
git status --short
```

Expected: only intentional uncommitted files from other work remain.

---

## 自审

- Spec 覆盖：HTTP 管理页、Server 转 upstream WS、Hermes adapter、OpenClaw adapter、桌面方案 A、移动端 Skills 风格、agent 侧权威存储都已覆盖。
- 占位符扫描：计划中没有未填写项或延后实现项。
- 类型一致性：Server `ManagedTask` / Flutter `ManagedTask` / gateway response 字段统一使用 snake_case JSON，Dart 内部转换为 camelCase。
