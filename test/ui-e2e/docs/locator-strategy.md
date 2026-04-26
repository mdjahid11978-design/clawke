# UI E2E 定位策略

日期：2026-04-26

## 结论

Clawke UI E2E 长期采用 **用户语义优先 + 少量 `Semantics.identifier` 兜底** 的定位策略。

系统级 UI E2E 的目标是模拟人工 QA 操作主干路径，因此默认不依赖 Flutter 内部 widget key。`ValueKey('ui_e2e_*')` 这类测试专用 key 不再作为新用例方案。

## 定位优先级

1. **可见文本**
   - 适合按钮、标题、菜单、卡片内容。
   - 示例：`新建会话`、`创建`、`允许`、`TypeScript`。

2. **可见语义**
   - 适合 icon button、输入框、无文字控件。
   - 优先用 tooltip、hint、语义 label。
   - 示例：tooltip `新建会话`、输入框 hint `输入消息...`。

3. **上下文内定位**
   - 当页面有重复按钮时，先定位稳定上下文，再在上下文内点击。
   - 示例：先找包含 `e2e-skill-lifecycle` 的技能卡片，再点卡片里的 `详情`、`删除` 或 `Switch`。

4. **`Semantics.identifier` 兜底**
   - 仅用于文本/tooltip/hint/上下文定位仍不稳定的控件。
   - 适合图标按钮、重复控件、动态列表中的技术目标。
   - 命名必须是产品语义，不是测试实现细节，例如：
     - `conversation.new`
     - `chat.input`
     - `chat.send`
     - `skill.card.toggle`
   - 添加 identifier 时必须不改变用户可见 UI，不影响屏幕阅读器含义。

5. **`ValueKey` 只用于 widget/unit test**
   - 系统级 UI E2E 不新增 `ui_e2e_*` key。
   - 旧的 key action 只作为历史兼容，不作为新 case 的默认写法。

## 允许的 case 写法

推荐：

```json
{ "action": "tap_text", "text": "新建技能", "exact": true }
{ "action": "enter_text_field", "index": 0, "text": "e2e-skill-lifecycle" }
{ "action": "tap_card_button", "cardText": "e2e-skill-lifecycle", "buttonText": "详情" }
{ "action": "tap_card_tooltip", "cardText": "e2e-task-lifecycle", "tooltip": "删除" }
{ "action": "wait_for_icon", "icon": "send" }
```

不推荐：

```json
{ "action": "tap_key", "key": "ui_e2e_new_conversation_button" }
{ "action": "wait_for_key", "key": "ui_e2e_send_button" }
```

## 选择标准

| 场景 | 首选定位 | 兜底 |
| --- | --- | --- |
| 唯一按钮或菜单 | `tap_text` | `tap_semantics_id` |
| 图标按钮 | tooltip / icon | `Semantics.identifier` |
| 输入框 | hint / label | `Semantics.identifier` |
| 卡片列表 | card text + descendant | `Semantics.identifier` |
| 本地化敏感路径 | 固定测试 locale 的文本 | `Semantics.identifier` |
| 重复控件 | 上下文内定位 | `Semantics.identifier` |

## 新增 action 规则

- 新 action 必须表达用户行为，不暴露 Flutter widget 细节。
- action 名称优先使用 `tap_text`、`tap_tooltip`、`enter_text_field_by_hint`、`tap_card_button`、`tap_semantics_id` 这类语义形式。
- 如果新增 `tap_semantics_id` / `wait_for_semantics_id`，必须使用 Flutter `find.bySemanticsIdentifier`。
- 新增 action 后必须补防回归测试，防止 case 回退到 `ui_e2e_*` key。

## 失败归因

定位失败不能直接提交产品 bug。必须先判断：

- case 是否仍依赖废弃 key。
- 文案是否因产品改版发生变化。
- 测试是否缺少上下文定位。
- 控件是否确实缺少可访问语义。

只有确认真实用户路径不可用，才提交产品 bug。否则归为测试基础设施问题并修 harness/case。

## 当前落地状态

- `create_conversation` 已改为 tooltip/text/输入框语义定位。
- `send_message` 已改为输入框 hint + send icon 定位。
- P0 审批/选择 case 已改为可见文本定位。
- P0 case 文件不再依赖 `ui_e2e_*` key。
- 防回归测试：`server/test/ui-e2e-harness-locators.test.js`。

## 参考

- Flutter integration test 使用 `flutter_test` finder API。
- Flutter `Semantics.identifier` 面向原生 accessibility hierarchy，可被 UIAutomator、XCUITest、Appium 等工具识别。
- Maestro Flutter 测试建议通过 Semantics Tree 测试 Flutter app。
