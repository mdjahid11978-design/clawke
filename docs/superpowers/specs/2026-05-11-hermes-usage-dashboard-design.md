# Hermes Usage 接入与仪表盘管理页设计

## 目标

分两阶段完成 Hermes token usage 能力：

1. 第一阶段只接入 Hermes 每条回复的 token usage，让聊天消息和现有统计链路能收到准确数据。
2. 第二阶段再建设“仪表盘管理页”，按 Gateway 维度展示 usage。PC 端采用原生管理页方案；移动端参考任务管理和技能管理的页面节奏。

## 当前事实

- Hermes `AIAgent.run_conversation()` 已返回 `input_tokens`、`output_tokens`、`cache_read_tokens`、`cache_write_tokens`、`reasoning_tokens`、`total_tokens`、`model`、`provider`。
- Clawke Server 已能把上游 `agent_text_done.usage` / `agent_text.usage` 翻译为 `usage_report`。
- 当前 Hermes gateway 只发送 `model/provider`，没有把 `run_conversation()` 的 usage 字段映射出去。
- 当前 `StatsCollector.recordTokens()` 只维护全局总量，没有按 Gateway、model/provider、最近会话维度组织数据。
- 现有 Dashboard 是 SDUI `DashboardView`，而任务管理和技能管理是 Flutter 原生管理页，使用 Gateway 选择、刷新、加载、错误态等一致交互。

## 阶段一：Hermes usage 接入

### 接入方式

在 `gateways/hermes/clawke/clawke_channel.py` 中增加一个小的 usage 映射函数，把 Hermes result 字段转换成 Clawke 已有格式：

- `input_tokens` → `usage.input`
- `output_tokens` → `usage.output`
- `cache_read_tokens` → `usage.cacheRead`
- `cache_write_tokens` → `usage.cacheWrite`
- `total_tokens` → `usage.total`
- `reasoning_tokens` → `usage.reasoning`

在 streaming 完成的 `agent_text_done` 和 non-streaming fallback 的 `agent_text` 中附加 `usage`。如果 result 不是 dict，或 usage 全部为 0，则不发送 `usage`，避免制造无意义统计。`model/provider` 保持现有字段。

### 第一阶段不做

- 不改 Hermes 配置，不要求用户打开额外开关。
- 不新增仪表盘 API。
- 不改 Flutter 仪表盘页面。
- 不改任务管理 / 技能管理。
- 不改变 Server ↔ Client 的聊天协议。

### 第一阶段验收

- Hermes 发一条消息后，Server 收到 `usage_report`。
- 聊天消息仍正常落库，客户端仍能收到最后一条 usage。
- OpenClaw 现有 usage 统计不回退。

### 第一阶段测试

- Hermes gateway 单测：覆盖 streaming `agent_text_done`、non-streaming `agent_text`、无 usage 三条路径。
- Server 相关测试：确认 `agent_text_done.usage` 仍会生成 `usage_report` 并触发 `recordTokens()`。
- Smoke：用 Hermes 发一条消息，确认日志或客户端出现 usage。

## 阶段二：仪表盘管理页

### Server 统计模型

扩展 `StatsCollector`，从“单一全局统计”升级为“全局 + Gateway 分组”的统计：

- 全局统计继续保留，兼容旧 Dashboard 和已有测试。
- 每个 Gateway 维护 total/today/hourly/daily 统计。
- 每个 Gateway 维护 model/provider 汇总，用于页面表格。
- 每次收到 `usage_report` 时，`MessageRouter` 用当前 `accountId/gatewayId` 调用 `recordTokens(gatewayId, usage, model, provider, conversationId)`。
- 最近会话用量只保留内存与持久化文件中的最近 N 条，v1 不做账单审计、导出和长期明细查询。

### 原生仪表盘管理页

新增 Flutter 原生 `DashboardManagementScreen`，替换主导航中的旧 SDUI Dashboard 展示；旧 `request_dashboard` 和 `DashboardView` 保留兼容，不作为主入口。

PC / 大屏：

- 左侧复用 `GatewaySelectorPane`，capability 使用 `dashboard` 或 `usage`。
- 右侧顶部是标题“仪表盘管理”和刷新按钮。
- 统计区显示总量、今日、输入、输出、cache。
- 趋图区显示小时/日 token 数据。
- 表格区显示 model/provider 汇总和最近会话用量。

移动端：

- 参考任务管理 / 技能管理：`AppBar` + 刷新按钮 + Gateway 选择按钮。
- 内容使用单列卡片：今日/总量、紧凑趋势图、模型汇总、最近会话用量。
- Gateway 不可用时复用 `GatewayUnavailablePanel` 的空态模式。

### API 和状态管理

按任务管理 / 技能管理模式新增 Dashboard 数据链路：

- Server 新增 `GET /api/dashboard/usage?gateway_id=...`。
- Client 新增 `DashboardApiService`、`dashboardProvider` / `DashboardController`、`UsageDashboard` 数据模型。
- 页面刷新时走 HTTP API，不依赖聊天 WebSocket 的 `request_dashboard`。
- Gateway 列表仍来自现有 `gatewayListProvider`，按 capability 过滤和排序。

响应数据最小结构：

```json
{
  "gateway_id": "hermes",
  "summary": {
    "input": 1200,
    "output": 800,
    "cacheRead": 300,
    "cacheWrite": 0,
    "reasoning": 0,
    "total": 2000
  },
  "today": { "input": 100, "output": 80, "cacheRead": 20, "cacheWrite": 0, "reasoning": 0, "total": 180 },
  "hourly": [{ "hour": "13:00", "total": 180 }],
  "daily": [{ "date": "2026-05-11", "input": 100, "output": 80, "cacheRead": 20 }],
  "models": [{ "model": "claude-sonnet", "provider": "anthropic", "input": 100, "output": 80, "total": 180 }],
  "recent": [{ "conversation_id": "hermes", "model": "claude-sonnet", "provider": "anthropic", "input": 100, "output": 80, "total": 180, "created_at": 1778500000000 }]
}
```

### 第二阶段不做

- 不做成本账单、导出、审计报表。
- 不删除旧 SDUI Dashboard；只是不再把它作为主导航的首选实现。

### 第二阶段验收

- `/api/dashboard/usage?gateway_id=hermes` 能返回 Hermes 的总量、今日、趋势、模型汇总和最近记录。
- PC 端仪表盘左侧可切换 Hermes/OpenClaw，右侧数据随 Gateway 刷新。
- 移动端仪表盘布局与任务/技能管理一致，支持刷新和 Gateway 选择。
- OpenClaw 现有 usage 统计不回退。

### 第二阶段测试

- Server 单测：覆盖 `MessageRouter` 按 gateway 记录 usage、`StatsCollector` 聚合、`GET /api/dashboard/usage` 返回结构。
- Flutter 单测/组件测试：覆盖 `DashboardApiService` 解析、Dashboard controller 切换 Gateway、页面空态/加载态。
- Smoke：分别用 Hermes 和 OpenClaw 发消息，打开仪表盘确认两个 Gateway 的用量分开显示。
