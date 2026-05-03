# Clawke UI E2E

这个目录管理 UI 层系统级集成测试。第一阶段只做手动触发，主力层是 Mock Gateway UI E2E。

## 测试边界

真实链路：

```text
Flutter UI -> Clawke Server -> WebSocket -> CUP -> Flutter 原生渲染
```

Mock 边界：

```text
Clawke Server -> Scripted Mock Gateway
```

不连接真实 Agent，不连接真实 LLM。测试系统只执行 UI、观察结果、输出报告，不负责修复。

## 定位策略

长期定位方案：**用户语义优先 + 少量 `Semantics.identifier` 兜底**。

- 默认用可见文本、tooltip、hint、卡片上下文定位。
- 不新增 `ValueKey('ui_e2e_*')` 作为系统级 UI E2E 定位方式。
- 图标、重复控件、动态列表等语义不足场景，再补 `Semantics.identifier`。

详见：`test/ui-e2e/docs/locator-strategy.md`。

## 一次性准备

```bash
cd server
npm install

cd ../client
dart run build_runner build --delete-conflicting-outputs
```

如果本地 Flutter/macOS 依赖已经生成过，第二条可以跳过。

## 手动运行

从仓库根目录执行：

```bash
./test/ui-e2e/tools/run.sh --case p0-send-message
```

通过时输出：

```text
PASS p0-send-message
Artifacts: test/ui-e2e/runs/<run-id>-p0-send-message
```

失败时输出 bug report 路径：

```text
FAIL p0-send-message
Bug report: test/ui-e2e/bug-reports/<run-id>-p0-send-message.md
```

跑全部用例并生成总报告：

```bash
./test/ui-e2e/tools/run-suite.sh
```

只跑部分用例：

```bash
./test/ui-e2e/tools/run-suite.sh --case p0-send-message --case p0-skills-management-lifecycle --case p0-tasks-management-lifecycle
```

suite 报告会写入：

```text
test/ui-e2e/suites/<suite-id>/report.html
test/ui-e2e/suites/<suite-id>/result.json
```

总报告包含 `total_count`、`passed_count`、`failed_count`，并链接每个单 case 的 `report.html`。

## 目录

- `tools/`: runner、Mock Gateway、启动脚本。
- `test-cases/`: 持久化用例。
- `templates/`: bug report 模板。
- `docs/`: 设计和实施文档。
- `runs/`: 每次运行日志和结果，本地保留，不提交。
- `bug-reports/`: 失败报告，本地保留，不提交。
- `suites/`: 多 case 汇总报告，本地保留，不提交。

## 用例元数据

每个 case 必须写清楚给人看的测试信息，报告会直接展示这些字段：

- `module`: 所属模块或页面，例如 `会话`、`技能管理`。
- `title`: 中文测试内容，说明这条 case 测什么。
- `objective`: 具体测试目标，说明要证明什么。
- `coverage`: 测试覆盖点列表。

失败报告和人工报告会生成“测试步骤 / 复现步骤”，用于人工或 AI 复现问题。

## 当前用例

- `p0-send-message`: 新建会话，发送消息，验证流式中间态和最终回复。
- `p0-chat-unread-badge`: Mock Gateway 主动推送消息，验证未选中、选中、后台页面和点击清零时的未读角标。
- `p0-notification-click-route`: 模拟原生远程通知点击 payload，验证自动定位到目标会话。
- `p0-disconnect-sync-recovers-stream-state`: 模拟流式回复收尾阶段断线，验证 sync 补回最终消息后清理 Thinking 和工具状态。
- `p0-openclaw-inline-approval`: OpenClaw markdown approval 代码块，点击原生审批按钮后以普通 chat 回复 `y`。
- `p0-openclaw-inline-choice`: OpenClaw markdown clarify 代码块，点击原生选项后以普通 chat 回复选项文本。
- `p0-hermes-approval`: Hermes 结构化 `approval_request`，点击原生审批按钮后透传 `approval_response`。
- `p0-hermes-choice`: Hermes 结构化 `clarify_request`，点击原生选项后透传 `clarify_response`。
- `p0-skills-management-lifecycle`: 技能中心新增、编辑、禁用、启用、删除 managed skill。
- `p0-tasks-management-lifecycle`: 任务管理新增、查看、编辑、暂停、启用、立即执行、执行记录、删除 managed task。
