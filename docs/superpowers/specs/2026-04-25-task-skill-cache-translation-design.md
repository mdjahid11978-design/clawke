# Task and Skill Cache with Skill Translation Design

日期：2026-04-25

## 背景

任务管理和技能中心现在都通过 Gateway 访问 agent 侧数据。Gateway 列表已经按 DB-first 方向设计：Client 先显示本地缓存，再异步从 Server 同步。任务列表和技能列表也应该采用同样的体验模型，但缓存范围必须更克制。

缓存会引入同步、删除、冲突和 stale data 风险。因此本设计只缓存低冲突、可由 Server 快照覆盖的数据：

- 任务只缓存任务定义，不缓存执行记录。
- 技能缓存 list metadata 和按需打开的 detail body。
- 翻译只针对 skill，不针对 task。
- 翻译结果 Server 和 Client 都存，Server 负责去重和后台任务，Client 负责 DB-first 显示。

## 已确认决策

- Task list 采用 DB-first 本地缓存。
- Task cache 只存任务定义，不存 `lastRun`、runs、output、output preview。
- Task 不做翻译。任务一般是用户自己定义的，已经是当前用户语言。
- Skill list/detail 采用 DB-first 本地缓存。
- Skill 支持本地多语言字段。
- Skill 翻译由 Server 负责缓存、去重、排队和调用模型。
- Skill `name` 不翻译，始终显示原文；第一版只翻译 `description`。
- Client 只声明当前 `locale` 和需要的字段。
- 翻译结果 Server 和 Client 都存。
- UI 优先显示当前语言翻译；没有翻译时显示原文。
- 增删改类操作保持 server-first，成功后再更新本地 DB。

## 目标

- 任务页打开时立即显示本地缓存任务定义，再异步刷新 Server 数据。
- 技能中心打开时立即显示本地缓存技能 metadata，再异步刷新 Server 数据。
- 技能详情打开时优先显示本地 detail body 和翻译字段，缺失时异步拉取并缓存。
- Server 对 skill 翻译结果做跨设备复用，避免重复调用模型。
- Client 对 skill 翻译结果做本地缓存，保证慢网和离线时仍能显示已有翻译。
- 保持任务执行链路由 agent/gateway 执行，Clawke 只管理和触发。

## 非目标

- 不缓存任务执行记录。
- 不缓存任务执行输出。
- 不翻译任务。
- 不做离线编辑队列。
- 不做 Client 侧大模型调用。
- 不在 Client 持有模型 API Key。
- 第一版不做翻译完成后的 WebSocket push，依赖下一次 sync/refresh 获取结果。

## 架构

### Client

Client 增加任务和技能本地缓存表。页面读取 DB 投影，Repository 在后台向 Server 同步。

通用策略：

1. 页面订阅 DB watch，先显示本地数据。
2. 页面或 Repository 触发异步 sync。
3. Server 返回当前 gateway 的完整快照。
4. Client upsert 返回项。
5. Client 删除该 `userId + gatewayId` 下本次快照缺失的本地项。
6. 修改类操作先调用 Server，成功后再更新 DB 或重新 sync。

Client 不判断翻译策略，只在请求中声明当前 locale。UI 读取 DB 时按当前 locale 做投影：

```text
display_name = name
display_description = translated_description ?? description
display_body = body
```

### Server

Server 是 Gateway 和翻译缓存的协调层。

任务数据：

- Server 不持久化任务真相。
- Server 从 Gateway 拉取任务列表，返回给 Client。
- Server 不做任务翻译。

技能数据：

- Server 从 Gateway 拉取技能 list/detail。
- Server 计算 source hash。
- Server 查询本地 translation cache。
- 已有 ready 翻译则随响应返回。
- 缺失或过期翻译则返回原文，并创建后台翻译 job。

翻译 job 由 Server 执行，模型 API Key 只留在 Server。Server 按 `skillId + locale + sourceHash + fieldSet` 去重，避免重复任务。

## Task Cache

### 缓存范围

缓存任务定义字段：

- `id`
- `gatewayId`
- `name`
- `schedule`
- `scheduleText`
- `prompt`
- `enabled`
- `status`
- `skills`
- `deliver`
- `createdAt`
- `updatedAt`

不缓存字段：

- `lastRun`
- `runs`
- `output`
- `outputPreview`
- 执行错误详情

### Client DB

建议表：`task_cache`

```text
user_id
gateway_id
task_id
name
schedule
schedule_text
prompt
enabled
status
skills_json
deliver
created_at
updated_at
synced_at
```

唯一键：

```text
user_id + gateway_id + task_id
```

### 同步规则

`GET /api/tasks?account_id=:gatewayId` 返回该 Gateway 的完整任务快照。

Client 同步：

```text
existing = DB tasks for userId + gatewayId
remote = Server tasks for gatewayId

upsert remote tasks
delete local tasks where task_id not in remote ids
```

### 修改规则

操作全部 server-first：

- create：Server 成功后 upsert 返回任务，或触发 sync。
- update：Server 成功后 upsert 返回任务，或触发 sync。
- delete：Server 成功后删除本地任务。
- set enabled：Server 成功后 upsert 返回任务，或触发 sync。
- run now：只触发 Server，不写任务缓存中的执行字段。

### 异步竞态

Provider 必须在请求返回时校验当前 selected gateway 是否仍然一致。

示例：

```text
request gateway = hermes
user switches to openclaw
hermes request returns
provider must ignore hermes response for current visible list
```

这条规则同时适用于 task 和 skill。

## Skill Cache

### 缓存范围

Skill list metadata：

- `id`
- `gatewayId`
- `name`
- `description`
- `category`
- `enabled`
- `source`
- `sourceLabel`
- `writable`
- `deletable`
- `path`
- `root`
- `updatedAt`
- `hasConflict`
- `sourceHash`

Skill detail：

- `body`
- `trigger`
- `content`
- `detailFetchedAt`

detail 按需缓存：只有用户打开详情或编辑时才拉取并写入。

### Client DB

建议表：`skill_cache`

```text
user_id
gateway_id
skill_id
name
description
category
enabled
source
source_label
writable
deletable
path
root
updated_at
has_conflict
trigger
body
content
source_hash
detail_fetched_at
synced_at
```

唯一键：

```text
user_id + gateway_id + skill_id
```

### 同步规则

`GET /api/skills?gateway_id=:gatewayId&locale=:locale` 返回该 Gateway 的 skill metadata 快照。

Client 同步：

```text
existing = DB skills for userId + gatewayId
remote = Server skills for gatewayId

upsert remote skills and returned localization
delete local skills where skill_id not in remote ids
```

详情同步：

```text
GET /api/skills/:skillId?gateway_id=:gatewayId&locale=:locale
```

返回原文 detail 和可用翻译。Client 写入 `skill_cache` 和 `skill_localizations`。

### 修改规则

操作全部 server-first：

- create：Server 成功后 upsert skill，必要时触发 sync。
- update：Server 成功后更新原文、sourceHash，并使旧翻译失效。
- delete：Server 成功后删除本地 skill 和相关 localization。
- enable/disable：Server 成功后更新 DB。

## Skill Translation

### 翻译范围

只翻译 skill 的 `description`。`name`、`trigger`、`body` 均保留原文。

第一版先翻译 metadata description；detail 请求也只复用/生成 description 翻译。

### Server DB

建议表：`skill_translation_cache`

```text
gateway_type
gateway_id
skill_id
locale
field_set
source_hash
translated_name
translated_description
translated_trigger
translated_body
status
error_code
error_message
created_at
updated_at
```

`translated_name`、`translated_trigger`、`translated_body` 字段保留为 schema 兼容字段，当前实现不写入、不用于 UI 展示。

建议表：`skill_translation_jobs`

```text
job_id
gateway_type
gateway_id
skill_id
locale
field_set
source_hash
status
attempt_count
last_error
created_at
updated_at
```

Server 去重键：

```text
gateway_type + gateway_id + skill_id + locale + source_hash + field_set
```

### Client DB

建议表：`skill_localizations`

```text
user_id
gateway_id
skill_id
locale
source_hash
translated_name
translated_description
translated_trigger
translated_body
status
error_code
error_message
updated_at
```

唯一键：

```text
user_id + gateway_id + skill_id + locale
```

### 翻译数据流

```text
Client sync skills with locale
  -> Server fetches source skills from Gateway
  -> Server computes sourceHash
  -> Server returns source + ready translations
  -> Server enqueues missing/expired translations
  -> Client upserts source + localization status/results
  -> UI shows translation if ready, otherwise source
  -> Next sync receives completed translations
```

### 状态

Translation status：

- `missing`：Client 没有翻译结果。
- `pending`：Server 已排队或处理中。
- `ready`：翻译可用。
- `failed`：翻译失败，UI fallback 原文。

UI 不展示普通 toast。翻译失败不阻塞技能使用，只在详情页或调试日志中可见。

## API 调整

### Task

现有任务接口保持不变，但响应中的 `lastRun` 不写入 Client task cache。

建议新增或约定 query：

```text
GET /api/tasks?account_id=:gatewayId
```

Server 返回任务定义快照。执行记录仍走：

```text
GET /api/tasks/:taskId/runs?account_id=:gatewayId
GET /api/tasks/:taskId/runs/:runId/output?account_id=:gatewayId
```

这些结果只进页面临时 state，不进本地 cache。

### Skill

建议：

```text
GET /api/skills?gateway_id=:gatewayId&locale=:locale
GET /api/skills/:skillId?gateway_id=:gatewayId&locale=:locale
```

响应包含：

```json
{
  "skills": [
    {
      "id": "ui/ui-ux-pro-max",
      "name": "ui-ux-pro-max",
      "description": "UI/UX design intelligence",
      "source_hash": "sha256:...",
      "localization": {
        "locale": "zh-CN",
        "status": "ready",
        "description": "用于 Web 和移动端的 UI/UX 设计智能"
      }
    }
  ]
}
```

如果翻译缺失：

```json
{
  "localization": {
    "locale": "zh-CN",
    "status": "pending"
  }
}
```

## Error Handling

- Gateway 不在线：页面不显示该 Gateway；如果当前选中 Gateway 断开，Controller 清空当前列表。
- Server 请求失败：保留 DB 旧数据，显示持久错误提示。
- Snapshot 删除：只删除当前 `userId + gatewayId` 范围内缺失项。
- 翻译失败：记录 `failed`，UI fallback 原文。
- sourceHash 变化：旧翻译失效，Server 重新排队，Client fallback 原文或继续显示旧翻译需明确标记为 stale。第一版建议不显示 stale 翻译。
- 请求竞态：请求返回时必须校验当前 gateway/scope 是否仍匹配。

## 测试策略

### Task cache

- DAO：upsert/watch/deleteMissing。
- Repository：DB-first stream，server snapshot 删除，本地不保存 `lastRun`。
- Controller：切换 Gateway 时旧请求返回不能覆盖新列表。
- 页面：无 Gateway、缓存先显示、刷新失败保留旧数据。
- Mutation：create/update/delete/enable 均 server-first。

### Skill cache

- DAO：metadata/detail/localization 分表写入和 watch 投影。
- Repository：list snapshot 删除，detail 按需缓存。
- Controller：切换 Gateway 时旧请求返回不能覆盖新列表。
- 页面：优先显示翻译，缺失 fallback 原文。

### Skill translation

- Server cache：同一 `sourceHash + locale + fieldSet` 去重。
- Server job：missing 入队，ready 不重复入队，failed 可重试。
- API：ready 翻译随响应返回，missing 返回 pending。
- Client：ready 写入 localization，pending 不覆盖已有 ready 同 hash。

### Safety

- Server tests 必须使用 `:memory:` 或临时 `CLAWKE_DATA_DIR`。
- 禁止测试操作 `server/data/clawke.db` 和真实用户 DB。
- 手工 E2E 使用临时数据目录，避免触发生产 DB cleanup。

## 实施顺序

1. 修复现有 Gateway 错误提示 severity：Gateway 错误用红色 `error`。
2. 修复 Task/Skill 异步请求竞态：返回时校验 selected gateway/scope。
3. 实现 Task list DB cache。
4. 实现 Skill list/detail DB cache。
5. 实现 Server skill translation cache/job。
6. 接入 Client skill localization DB 投影。
7. 补完整 targeted tests。

## 验收标准

- 任务页可在 Server 慢或失败时先显示本地任务定义缓存。
- 任务页不缓存和不恢复任何执行记录。
- Server 删除任务后，下一次 sync 会删除本地缓存。
- 技能中心可先显示本地 skill metadata。
- 技能详情可先显示本地 body。
- Skill 翻译 ready 时优先显示翻译，missing/pending/failed 时显示原文。
- Server 不重复翻译同一 sourceHash。
- Client 不调用模型，不持有模型 API Key。
- 相关 server/client/gateway targeted tests 通过。
