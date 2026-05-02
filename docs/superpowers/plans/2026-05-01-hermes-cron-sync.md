# Hermes Cron Sync 实施计划

> **给执行 Agent 的要求：** 实施本计划时必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项完成。步骤使用 checkbox（`- [x]`）跟踪。

**目标：** 不修改 Hermes 源码、不修改 Hermes 主 Gateway 启动命令，在 Clawke Hermes Gateway 侧监听 Hermes cron output 文件，并把自动定时任务结果投递到配置的 Clawke 会话。

**架构：** Hermes Clawke Gateway 负责发现 Hermes cron output、维护本地投递状态、控制重试、上报报警。Clawke Server 负责通用 `gateway_alert` 的同 Gateway 路由和消息落库。Client 现有“交付会话”校验 UI 不属于本计划范围。

**技术栈：** Gateway 使用 Python 标准库 `sqlite3` / `json` / `pathlib` / `asyncio`；Server 使用 TypeScript 和现有 MessageRouter；测试使用 Python `pytest`、Node `node:test`。

---

## 已锁定需求

- 不修改 Hermes 源码：
  - `~/.hermes/hermes-agent`
  - `/Users/samy/MyProject/ai/clawke_extends/hermes-agent`
- 不修改 Hermes 主 Gateway 启动命令。
- Cron sync 状态不写入 Clawke Server DB。
- 新代码、新协议字段、新日志、新测试、新文档必须优先使用 `gateway_id` / `gatewayId` / Gateway ID。
- `account_id` 只允许用于现有旧协议兼容或迁移桥接。
- 首次运行不补发历史 output。
- 每 5 秒轮询一次。
- 只处理 `deliver = conversation:<uuid>` 的 Hermes job。
- 扫描进度保存到：

```text
~/.clawke/gateway/hermes/cron-sync.json
```

- 每条 output 的投递状态保存到：

```text
~/.clawke/gateway/hermes/cron-sync.db
```

- JSON 配置字段名固定为：

```json
{
  "gateway_id": "hermes",
  "last_scanned_mtime": 1777626000.123
}
```

- 只有发现新 output 并成功写入 SQLite 后，才更新 `last_scanned_mtime`。
- 没发现新 output 时，不更新 `cron-sync.json`。
- 每条 output 最多投递 3 次。
- 第 1 次失败后 1 分钟重试。
- 第 2 次失败后 5 分钟重试。
- 第 3 次失败后标记 `failed`，停止自动投递。
- 每次计入次数的投递失败都发送一次通用 `gateway_alert`。
- 报警发送失败不能递归触发新的报警。
- Clawke WS 断开时不消耗 3 次投递次数，因为用户也收不到报警。

---

## 文件规划

### 新增文件

- `gateways/hermes/clawke/cron_sync.py`
  - Hermes cron output 扫描器。
  - 负责 JSON 扫描进度、SQLite 投递状态、response 提取、重试调度、delivery callback、alert callback。

- `gateways/hermes/clawke/test_cron_sync.py`
  - 覆盖首次不补历史、新 output 入库、重启恢复、失败重试、报警、response 提取。

- `server/src/services/gateway-alert-service.ts`
  - 通用 Gateway Alert 服务。
  - 负责同 Gateway 会话选择、Markdown 报警内容构建。

### 修改文件

- `gateways/hermes/clawke/clawke_channel.py`
  - 启停 `HermesCronOutputSyncer`。
  - 新增通用 `_send_gateway_alert(...)`。
  - 复用现有 `_deliver_task_result(...)` 投递 cron sync 结果。

- `gateways/hermes/clawke/task_adapter.py`
  - 手动执行任务保存 output 后，把对应 output 标记为已投递，避免 syncer 重复投递。

- `gateways/hermes/clawke/test_clawke_channel.py`
  - 覆盖 gateway alert payload 和 syncer 生命周期。

- `gateways/hermes/clawke/test_task_adapter.py`
  - 覆盖手动执行后标记 output delivered。

- `server/src/types/openclaw.ts`
  - 增加 `gateway_alert` 类型和字段。

- `server/src/translator/cup-encoder.ts`
  - 把 `gateway_alert` 编码成普通可存储文本消息。

- `server/src/upstream/message-router.ts`
  - 对 `gateway_alert` 做同 Gateway 路由。
  - 修复未知 conversation fallback，禁止回退到全局最近会话。

- `server/src/index.ts`
  - 上游 Gateway 身份读取改为优先 `gateway_id`，兼容旧 `account_id`。

- `server/test/ts-integration.test.js`
  - 覆盖 `gateway_alert` 编码、路由、同 Gateway fallback、去重。

---

## 数据设计

### `cron-sync.json`

路径：

```text
~/.clawke/gateway/hermes/cron-sync.json
```

内容：

```json
{
  "gateway_id": "hermes",
  "last_scanned_mtime": 1777626000.123
}
```

规则：

- 文件不存在：创建父目录，写入 `last_scanned_mtime = now`，不补发历史。
- 文件存在：启动时只读取，不修改。
- 每轮扫描：只发现 `mtime > last_scanned_mtime` 的文件。
- 新 output 全部成功写入 SQLite 后：更新为这批新 output 的最大 `mtime`。
- 没有新 output：不更新文件。
- JSON 损坏：发送一次 `gateway_alert`，重新初始化为 `now`，不补发历史。

### `cron-sync.db`

路径：

```text
~/.clawke/gateway/hermes/cron-sync.db
```

表结构：

```sql
CREATE TABLE IF NOT EXISTS cron_delivery_state (
  gateway_id TEXT NOT NULL,
  job_id TEXT NOT NULL,
  output_filename TEXT NOT NULL,
  output_path TEXT NOT NULL,
  output_mtime REAL NOT NULL,
  job_name TEXT,
  conversation_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'delivered', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at REAL,
  last_error TEXT,
  discovered_at REAL NOT NULL,
  last_attempt_at REAL,
  delivered_at REAL,
  PRIMARY KEY (gateway_id, job_id, output_filename)
);

CREATE INDEX IF NOT EXISTS idx_cron_delivery_due
  ON cron_delivery_state (gateway_id, status, next_retry_at, attempts);
```

output 唯一标识：

```text
gateway_id + job_id + output_filename
```

不使用 `output_sha256`。Hermes 当前 output 文件名已经是时间戳格式：

```text
~/.hermes/cron/output/<job_id>/<YYYY-MM-DD_HH-MM-SS>.md
```

示例：

```text
~/.hermes/cron/output/a347d07dd7c0/2026-05-01_17-16-06.md
```

---

## Task 1：实现 Server 通用 Gateway Alert

**文件：**

- 新建：`server/src/services/gateway-alert-service.ts`
- 修改：`server/src/types/openclaw.ts`
- 修改：`server/src/translator/cup-encoder.ts`
- 修改：`server/src/upstream/message-router.ts`
- 修改：`server/src/index.ts`
- 测试：`server/test/ts-integration.test.js`

- [x] **Step 1：扩展上游消息类型**

在 `OpenClawMessageType` 增加：

```ts
| 'gateway_alert'
```

在 `OpenClawMessage` 增加字段：

```ts
gateway_id?: string;
severity?: 'info' | 'warning' | 'error';
source?: string;
title?: string;
message?: string;
target_conversation_id?: string;
dedupe_key?: string;
metadata?: Record<string, unknown>;
```

要求：

- 新增 alert 字段使用 `gateway_id`。
- 不新增新的 `account_id` alert 字段。
- 旧协议中已有的 `account_id` 不在本任务里重命名。

- [x] **Step 2：新增 Gateway Alert 服务**

新建 `server/src/services/gateway-alert-service.ts`，导出：

```ts
export interface GatewayAlertInput {
  gatewayId: string;
  severity: 'info' | 'warning' | 'error';
  source: string;
  title: string;
  message: string;
  targetConversationId?: string;
  dedupeKey?: string;
  metadata?: Record<string, unknown>;
}

export function buildGatewayAlertMarkdown(alert: GatewayAlertInput): string;

export function resolveGatewayAlertConversation(
  conversationStore: ConversationStore,
  gatewayId: string,
  targetConversationId?: string,
): string;
```

会话选择规则：

- 如果 `targetConversationId` 存在，并且 `conversationStore.get(targetConversationId)?.accountId === gatewayId`，使用它。
- 如果目标不存在，或属于其它 Gateway，使用 `conversationStore.listByAccount(gatewayId)[0]`。
- 如果当前 Gateway 没有任何会话，创建默认会话：

```ts
conversationStore.create(gatewayId, 'ai', gatewayId, gatewayId)
```

- 禁止使用 `conversationStore.list()` 做全局 fallback。

Markdown 格式：

```md
### Gateway Alert: <title>

**Severity:** <severity>
**Source:** <source>

<message>
```

- [x] **Step 3：编码 `gateway_alert`**

在 `translateToCup(...)` 增加 `gateway_alert` 分支：

- `message_id` 使用：

```ts
msg.dedupe_key || msg.message_id || `alert_${Date.now()}`
```

- 使用 `buildGatewayAlertMarkdown(...)` 生成存储内容。
- 输出 `text_delta` + `text_done`，行为与 `agent_text` 一致。
- `metadata.needsStore.fullText` 写 Markdown 报警内容。
- `metadata.needsStore.upstreamMsgId` 写 `dedupe_key`，用于 DB 去重。

- [x] **Step 4：MessageRouter 路由 alert**

在通用 unknown conversation fallback 前处理 `gateway_alert`：

- 识别 `msg.type === 'gateway_alert'`。
- `gatewayId = msg.gateway_id || currentGatewayId`。
- 用 `resolveGatewayAlertConversation(...)` 解析会话。
- 把解析后的 conversation 写入 `msg.conversation_id`。
- 再交给 `translateToCup(...)`。

同时修复普通未知会话 fallback：

- 不能再用全局 `conversationStore.list()`。
- 改成 `conversationStore.listByAccount(currentGatewayId)`。
- 没有同 Gateway 会话时创建默认会话。
- 日志里带 `gateway=<gatewayId>`。

- [x] **Step 5：Server 上游入口兼容 `gateway_id`**

在 `server/src/index.ts` 上游消息入口改为：

```ts
const gatewayId = (payload.gateway_id as string) || (payload.account_id as string) || 'default';
messageRouter.handleUpstreamMessage(payload as any, gatewayId);
```

说明：

- 旧代码内部参数名可以暂时还是 `accountId`，不做大范围重命名。
- 新增局部变量和新逻辑使用 `gatewayId`。

- [x] **Step 6：新增 Server 测试**

在 `server/test/ts-integration.test.js` 增加测试：

- `gateway_alert stores alert in target conversation under same gateway`
- `gateway_alert target from another gateway falls back to same gateway`
- `unknown conversation fallback uses same gateway latest conversation`
- `gateway_alert dedupe_key prevents duplicate stored messages`

测试要求：

- 必须使用 `Database(':memory:')`。
- 不能访问生产 DB。

- [x] **Step 7：验证 Server**

运行：

```bash
cd server
npm run build
node --test --test-concurrency=1 --test-force-exit test/ts-integration.test.js
```

预期：

- TypeScript 编译通过。
- 新增 alert 测试通过。
- 现有集成测试不回归。

---

## Task 2：实现 Hermes Cron Sync 本地状态

**文件：**

- 新建：`gateways/hermes/clawke/cron_sync.py`
- 测试：`gateways/hermes/clawke/test_cron_sync.py`

- [x] **Step 1：新增路径 helper**

在 `cron_sync.py` 增加：

```python
def default_sync_dir() -> Path:
    return Path.home() / ".clawke" / "gateway" / "hermes"

def default_db_path() -> Path:
    return default_sync_dir() / "cron-sync.db"

def default_config_path() -> Path:
    return default_sync_dir() / "cron-sync.json"
```

- [x] **Step 2：实现 JSON 配置存储**

新增 `CronSyncConfigStore`：

```python
class CronSyncConfigStore:
    def __init__(self, path: Path, gateway_id: str):
        self.path = path
        self.gateway_id = gateway_id

    def load_or_initialize(self, now: float) -> dict[str, Any]:
        ...

    def update_last_scanned_mtime(self, mtime: float) -> None:
        ...
```

行为：

- 文件不存在：创建父目录，写：

```json
{
  "gateway_id": "hermes",
  "last_scanned_mtime": 1777626000.123
}
```

- 文件存在：读取并返回，不修改。
- JSON 损坏：抛出 `CronSyncConfigError`，由 syncer 上层报警并重新初始化。

- [x] **Step 3：实现 SQLite 状态存储**

新增 `CronSyncStateStore`：

```python
class CronSyncStateStore:
    def __init__(self, path: Path):
        self.path = path

    def connect(self) -> None:
        ...

    def close(self) -> None:
        ...

    def insert_pending_output(self, record: CronOutputRecord) -> bool:
        ...

    def list_due_outputs(self, gateway_id: str, now: float) -> list[CronDeliveryRecord]:
        ...

    def mark_delivered(self, record: CronDeliveryRecord, now: float) -> None:
        ...

    def mark_failed_attempt(self, record: CronDeliveryRecord, error: str, now: float) -> int:
        ...
```

规则：

- `insert_pending_output(...)` 只有新插入时返回 `True`。
- `mark_failed_attempt(...)`：
  - `attempts += 1`
  - 写 `last_error`
  - 写 `last_attempt_at`
  - 第 1 次失败：`next_retry_at = now + 60`
  - 第 2 次失败：`next_retry_at = now + 300`
  - 第 3 次失败：`status = failed`，`next_retry_at = NULL`

- [x] **Step 4：新增状态存储测试**

在 `test_cron_sync.py` 增加：

- 缺失 JSON 会初始化 `last_scanned_mtime = now`。
- 已存在 JSON 只读取，不改文件内容。
- SQLite 插入基于 `(gateway_id, job_id, output_filename)` 幂等。
- 失败状态按 `pending -> pending -> failed` 转换。
- 第 1、2 次失败写正确的 `next_retry_at`。

- [x] **Step 5：验证状态测试**

运行：

```bash
cd gateways/hermes/clawke
python3 -m pytest test_cron_sync.py -q
```

预期：

- 测试只使用 `tmp_path`。
- 不读写真实 `~/.clawke`。

---

## Task 3：实现 output 发现和 Response 提取

**文件：**

- 修改：`gateways/hermes/clawke/cron_sync.py`
- 测试：`gateways/hermes/clawke/test_cron_sync.py`

- [x] **Step 1：定义数据结构**

新增 dataclass：

```python
@dataclass(frozen=True)
class CronJobTarget:
    job_id: str
    job_name: str
    conversation_id: str

@dataclass(frozen=True)
class CronOutputRecord:
    gateway_id: str
    job_id: str
    output_filename: str
    output_path: str
    output_mtime: float
    job_name: str
    conversation_id: str
    discovered_at: float
```

- [x] **Step 2：解析 delivery target**

新增：

```python
def parse_conversation_delivery(deliver: Any) -> str | None:
    if isinstance(deliver, dict):
        target = str(deliver.get("to") or deliver.get("channel") or "")
    else:
        target = str(deliver or "")
    if not target.startswith("conversation:"):
        return None
    conversation_id = target.split(":", 1)[1].strip()
    return conversation_id or None
```

- [x] **Step 3：发现新 output**

新增：

```python
def discover_new_outputs(
    gateway_id: str,
    jobs: Iterable[dict[str, Any]],
    output_dir: Path,
    last_scanned_mtime: float,
    now: float,
) -> list[CronOutputRecord]:
    ...
```

规则：

- 只处理 `parse_conversation_delivery(job.get("deliver"))` 有值的 job。
- 忽略包含路径分隔符、绝对路径、`.`、`..` 的 job id。
- 只扫描：

```text
output_dir / job_id / "*.md"
```

- 只返回：

```text
path.stat().st_mtime > last_scanned_mtime
```

- 按 `(output_mtime, output_filename)` 升序。
- 不扫描当前 job 列表以外的 output 子目录。

- [x] **Step 4：提取 `## Response`**

新增：

```python
def extract_cron_response(text: str) -> str:
    marker = "## Response"
    ...
```

规则：

- 找到第一个 `## Response` 后，返回其后的文本。
- 去掉首尾空白。
- 没有 marker 时，返回全文 trim 后结果。
- trim 后内容包含 `[SILENT]`（大小写不敏感）时，返回空字符串。

- [x] **Step 5：新增发现测试**

覆盖：

- 非 `conversation:` 的 deliver 被忽略。
- `conversation:<uuid>` 的 job 能发现新 `.md`。
- `mtime <= last_scanned_mtime` 的旧文件被忽略。
- 不在 job 列表里的 output 子目录被忽略。
- `[SILENT]` 返回空字符串。

- [x] **Step 6：验证发现测试**

运行：

```bash
cd gateways/hermes/clawke
python3 -m pytest test_cron_sync.py -q
```

---

## Task 4：实现 Cron Syncer 投递循环

**文件：**

- 修改：`gateways/hermes/clawke/cron_sync.py`
- 测试：`gateways/hermes/clawke/test_cron_sync.py`

- [x] **Step 1：定义 callback 类型**

新增：

```python
DeliveryCallback = Callable[[dict[str, Any], str], str | None]
AlertCallback = Callable[[dict[str, Any]], None]
JobsProvider = Callable[[], Any]
```

说明：

- `DeliveryCallback` 成功返回 `None`。
- 失败返回错误字符串。

- [x] **Step 2：实现 `HermesCronOutputSyncer`**

构造函数：

```python
class HermesCronOutputSyncer:
    def __init__(
        self,
        gateway_id: str,
        jobs_provider: JobsProvider,
        deliver_result: DeliveryCallback,
        send_alert: AlertCallback,
        config_path: Path | None = None,
        db_path: Path | None = None,
        poll_interval_seconds: float = 5.0,
    ):
        ...
```

方法：

```python
async def start(self) -> None:
    ...

async def stop(self) -> None:
    ...

def scan_once(self, now: float | None = None) -> None:
    ...
```

- [x] **Step 3：实现扫描阶段**

`scan_once(...)` 执行：

1. `load_or_initialize(...)` 读取或初始化 `cron-sync.json`。
2. 调用 `jobs_provider().list_jobs(include_disabled=True)`。
3. 读取 `Path(jobs_provider().OUTPUT_DIR)`。
4. 发现 `mtime > last_scanned_mtime` 的 output。
5. 每个新 output 先写入 SQLite，`status = pending`。
6. 如果至少发现一个新 output，并且全部成功入库，把 `last_scanned_mtime` 更新到这批文件最大 `mtime`。

JSON 损坏时：

- 发一次 `gateway_alert`，`source = "cron_sync_config"`。
- 重新初始化为 `last_scanned_mtime = now`。
- 本轮返回，不补历史。

- [x] **Step 4：实现投递阶段**

扫描后处理 due rows：

- `gateway_id` 匹配。
- `status = 'pending'`。
- `attempts < 3`。
- `next_retry_at IS NULL OR next_retry_at <= now`。

对每条 due row：

1. 读取 output 文件。
2. 提取 `## Response` 后内容。
3. 内容为空时直接 `mark_delivered`，不发送。
4. 调用 `deliver_result(job, body)`。
5. 成功：`mark_delivered`。
6. 失败：`mark_failed_attempt`。
7. 失败后发一次 `gateway_alert`。

如果 output 文件不存在：

- 计为失败，错误为 `output file missing`。

- [x] **Step 5：定义报警 payload**

Syncer 调用 alert callback 的 payload：

```python
{
    "severity": "error",
    "source": "cron_delivery",
    "title": "Hermes cron delivery failed",
    "message": "...",
    "target_conversation_id": conversation_id,
    "dedupe_key": f"cron_delivery:{job_id}:{output_filename}:attempt:{attempts}",
    "metadata": {
        "job_id": job_id,
        "job_name": job_name,
        "output_filename": output_filename,
        "attempts": attempts,
        "max_attempts": 3,
    },
}
```

`message` 必须包含：

- Job name
- Job ID
- Output file name
- Target conversation
- Attempt count，例如 `2 / 3`
- Error
- 第 3 次失败时说明自动投递已经停止

- [x] **Step 6：WS 断开时不消耗重试次数**

Gateway 集成层需要让 delivery 在 WS 断开时返回特殊不可用结果。

规则：

- Clawke WS 断开：不增加 `attempts`。
- 不发 alert。
- row 保持 `pending`。
- 下次 poll 时继续尝试。

原因：WS 断开时用户收不到报警，不能把 3 次机会消耗掉。

- [x] **Step 7：新增 syncer 测试**

覆盖：

- 首次运行初始化 JSON 为 now，不插入旧 output。
- 新 output 会入库并投递。
- 新 output 入库后，`last_scanned_mtime` 更新为最大 mtime。
- 没有新 output 时 JSON 不变。
- pending row 重启后继续投递。
- 第 1 次失败，60 秒后重试，并发送 alert。
- 第 2 次失败，300 秒后重试，并发送 alert。
- 第 3 次失败，标记 failed，并发送最终 alert。
- WS 不可用时 attempts 不变。

- [x] **Step 8：验证 syncer**

运行：

```bash
cd gateways/hermes/clawke
python3 -m pytest test_cron_sync.py -q
```

---

## Task 5：接入 Hermes Clawke Gateway

**文件：**

- 修改：`gateways/hermes/clawke/clawke_channel.py`
- 修改：`gateways/hermes/clawke/test_clawke_channel.py`

- [x] **Step 1：新增 syncer 字段**

在 `ClawkeHermesGateway.__init__` 增加：

```python
self._cron_syncer: Any = None
self._cron_sync_task: asyncio.Task | None = None
```

新增 helper：

```python
def _gateway_id(self) -> str:
    return str(getattr(self.config, "gateway_id", "") or getattr(self.config, "account_id", "") or "hermes")
```

说明：

- 新代码调用 `_gateway_id()`。
- `self.config.account_id` 是历史兼容字段。

- [x] **Step 2：新增 `_get_cron_syncer`**

```python
def _get_cron_syncer(self):
    if self._cron_syncer is None:
        from cron_sync import HermesCronOutputSyncer
        self._cron_syncer = HermesCronOutputSyncer(
            gateway_id=self._gateway_id(),
            jobs_provider=self._get_task_adapter()._jobs,
            deliver_result=self._deliver_task_result,
            send_alert=self._send_gateway_alert,
        )
    return self._cron_syncer
```

- [x] **Step 3：启动 syncer**

在 `start()` 设置 `_loop` 后启动：

```python
if self._cron_sync_task is None or self._cron_sync_task.done():
    self._cron_sync_task = asyncio.create_task(self._get_cron_syncer().start())
```

不能重复启动多个 sync task。

- [x] **Step 4：停止 syncer**

在 `stop()` 里：

- 如果 `_cron_syncer` 存在，调用 `await self._cron_syncer.stop()`。
- 如果 `_cron_sync_task` 存在，cancel 并 await。
- 使用 `return_exceptions=True`。
- 然后继续现有 approval、agent、WS 清理。

- [x] **Step 5：新增 `_send_gateway_alert`**

```python
def _send_gateway_alert(self, alert: dict[str, Any]) -> None:
    payload = {
        "type": "gateway_alert",
        "gateway_id": self._gateway_id(),
        "message_id": alert.get("dedupe_key") or f"gateway_alert_{int(time.time() * 1000)}",
        "severity": alert.get("severity", "error"),
        "source": alert.get("source", "gateway"),
        "title": alert.get("title", "Gateway alert"),
        "message": alert.get("message", ""),
        "target_conversation_id": alert.get("target_conversation_id"),
        "dedupe_key": alert.get("dedupe_key"),
        "metadata": alert.get("metadata") or {},
    }
    ...
```

要求：

- 用现有 `_send(...)` 发送。
- 不在发送失败时递归调用 `_send_gateway_alert`。
- payload 不带新的 `account_id`。

- [x] **Step 6：保留现有 delivery 兼容**

`_deliver_task_result(...)` 目前发送 `agent_text` 时仍包含 `account_id`。这是现有 Server 存储协议需要的旧字段，本任务不改。

新增 syncer 和 alert 代码必须使用 `gateway_id`。

- [x] **Step 7：新增 Gateway 测试**

在 `test_clawke_channel.py` 增加：

- `_send_gateway_alert sends gateway_alert with gateway_id and no account_id`
- `start creates one cron sync task`
- `stop stops cron sync task`

- [x] **Step 8：验证 Gateway**

运行：

```bash
cd gateways/hermes/clawke
python3 -m pytest test_clawke_channel.py -q
```

---

## Task 6：防止手动执行重复投递

**文件：**

- 修改：`gateways/hermes/clawke/task_adapter.py`
- 修改：`gateways/hermes/clawke/test_task_adapter.py`

- [x] **Step 1：给 TaskAdapter 增加可选 marker**

扩展 `HermesTaskAdapter.__init__`：

```python
def __init__(
    self,
    deliver_result: Callable[[dict[str, Any], str], str | None] | None = None,
    mark_output_delivered: Callable[[dict[str, Any], Path], None] | None = None,
):
    self._deliver_result = deliver_result
    self._mark_output_delivered = mark_output_delivered
```

- [x] **Step 2：保存 output path**

把：

```python
if output and hasattr(jobs, "save_job_output"):
    jobs.save_job_output(task_id, output)
```

改为：

```python
saved_output_path = None
if output and hasattr(jobs, "save_job_output"):
    saved_output_path = jobs.save_job_output(task_id, output)
```

- [x] **Step 3：成功 delivery 后标记 delivered**

条件：

- `saved_output_path` 存在。
- `delivery_error is None`。
- `_mark_output_delivered` 存在。

执行：

```python
self._mark_output_delivered(raw_job, Path(saved_output_path))
```

如果 marker 失败：

- 只记录 warning。
- 不影响手动执行结果。

- [x] **Step 4：Gateway 注入 marker**

在 `clawke_channel.py` 创建 `HermesTaskAdapter` 时传入：

```python
self._task_adapter = HermesTaskAdapter(
    deliver_result=self._deliver_task_result,
    mark_output_delivered=self._get_cron_syncer().mark_manual_output_delivered,
)
```

`mark_manual_output_delivered(...)` 行为：

- 使用 output 文件名和 mtime。
- 插入或更新 `cron_delivery_state`。
- 设置 `status = delivered`。

- [x] **Step 5：新增 TaskAdapter 测试**

覆盖：

- 手动执行成功投递后调用 `mark_output_delivered`。
- 手动执行 delivery error 时不标记 delivered。
- marker 抛异常时不导致任务运行失败。

- [x] **Step 6：验证 TaskAdapter**

运行：

```bash
cd gateways/hermes/clawke
python3 -m pytest test_task_adapter.py -q
```

---

## Task 7：完整验证

**文件：**

- 不新增文件。

- [x] **Step 1：运行 Hermes Gateway 相关测试**

```bash
cd gateways/hermes/clawke
python3 -m pytest test_cron_sync.py test_clawke_channel.py test_task_adapter.py -q
```

预期：

- 所选 Python 测试全部通过。

- [x] **Step 2：运行 Server 测试**

```bash
cd server
npm run build
npm test
```

预期：

- TypeScript 编译通过。
- Node 测试通过。

- [x] **Step 3：本地手动 smoke test**

只使用本地开发环境。不要修改 Hermes 源码，不要改 Hermes 主 Gateway 启动命令。

1. 启动或重启 Clawke Server 和 Hermes Clawke Gateway。
2. 确认文件存在：

```text
~/.clawke/gateway/hermes/cron-sync.json
~/.clawke/gateway/hermes/cron-sync.db
```

3. 创建或使用一个 Hermes cron job：

```text
deliver = conversation:<valid-hermes-conversation-uuid>
```

4. 等待或触发生成新 output：

```text
~/.hermes/cron/output/<job_id>/<YYYY-MM-DD_HH-MM-SS>.md
```

5. 确认目标 Clawke 会话收到 `## Response` 后的内容。
6. 查询 `cron_delivery_state.status = delivered`。
7. 再等一次 poll，确认没有重复消息。

- [x] **Step 4：失败 smoke test**

使用缺失 output 文件造真实投递失败。无效 Hermes conversation id 会被 Server 同 Gateway fallback，不再视为投递失败。

预期：

- Syncer 产生投递失败。
- Hermes Gateway 会话收到 `gateway_alert`。
- 失败累计 3 次后停止。
- `cron_delivery_state.status = failed`。
- 消息不会路由到 OpenClaw 或其它 Gateway 会话。

---

## 验收标准

- Hermes 自动 cron output 能投递到配置的 Clawke 会话。
- 不修改 Hermes 源码。
- 不修改 Hermes 主 Gateway 启动命令。
- 首次运行不补发历史 output。
- 重启不会丢失上次 `last_scanned_mtime` 之后生成、但还没投递完成的 output。
- 手动执行不会被 syncer 重复投递。
- 每次计入次数的投递失败都会发送通用 `gateway_alert`。
- 每条 output 失败 3 次后停止重试。
- alert 和 fallback 路由绝不跨 Gateway。
- 新增协议字段使用 `gateway_id`，不新增公开 `account_id` 字段。
- 所有列出的 Python 和 Server 测试通过。

---

## 实施注意事项

- `GatewayConfig.account_id` 是历史字段。新 Hermes cron sync 代码必须通过 `_gateway_id()` 获取 Gateway ID。
- 现有 CUP 和消息 DB 仍有 `account_id` 列，本计划不做数据库字段重命名。
- Syncer 使用 Python 标准库 `sqlite3`，不要新增依赖。
- 即使没有新 output，也要继续轮询，因为可能有 due retry rows。
- Clawke WS 断开时不要消耗 3 次投递机会。
- 日志保持英文。
- 如需新增代码注释，必须中英双语。
