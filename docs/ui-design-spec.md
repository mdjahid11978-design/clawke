# Clawke UI Design Spec

本文档记录 Clawke 原生客户端的通用 UI 规范。新增页面或调整页面时优先遵守本规范；如果需要偏离，必须先做 HTML demo 并确认。

## 顶部 AppBar 规范

适用范围：设置页、详情页、编辑页、新建页、二级页面，以及从列表页进入的全屏覆盖式页面。

### 基本结构

- 使用 Flutter 标准 `AppBar`，不要自绘一整块顶部工具栏。
- 左侧只放返回箭头，不在 AppBar 左侧显示“返回xxx”长文本。
- 标题居中显示，标题描述当前页面类型，例如 `技能详情`、`编辑技能`、`新建会话`、`设置`。
- 右侧只放当前页面的主动作；桌面端和移动端统一使用“图标 + 文本”，例如 `编辑图标 + 编辑`、`保存图标 + 保存`、`创建图标 + 创建`。
- 右侧动作使用主题主色；不可用时使用 disabled 样式，不要再加胶囊背景。
- 如果某个页面当前没有可执行的主动作，例如只读详情页不可编辑，则右侧动作直接不显示，不渲染 disabled 按钮。
- AppBar 背景使用 `colorScheme.surface`，`surfaceTintColor` 必须为 `Colors.transparent`。

### 内容区标题

- AppBar 标题用于说明“当前页面是什么”。
- 二级页面内容区默认不再放大标题和说明文案，避免和 AppBar 重复。
- 详情页、编辑页、新建页应直接进入主体卡片或表单。
- 实体名称放在详情字段或表单字段中展示，不额外做一块大 Header。

### 禁止做法

- 不要在内容区顶部放 `返回技能列表` 这种 TextButton 作为主返回入口。
- 不要把页面标题、描述、编辑按钮混在一个自定义大 Header 里。
- 不要在 AppBar 右侧使用大号胶囊按钮，除非它是一级页面的主 CTA。
- 不要让同一个页面同时出现 AppBar 标题和功能重复的大 Header 标题。
- 不要在详情页、编辑页、新建页顶部重复放“页面大标题 + 一句说明”。

### 推荐 Flutter 写法

```dart
Scaffold(
  backgroundColor: colorScheme.surface,
  appBar: AppBar(
    title: Text(context.l10n.skillDetail),
    backgroundColor: colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    actions: [
      TextButton(
        onPressed: canEdit ? onEdit : null,
        child: Text(
          context.l10n.edit,
          style: TextStyle(
            color: canEdit ? colorScheme.primary : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  ),
  body: content,
)
```

### 页面示例

```text
┌────────────────────────────────────────────────────────────┐
│  ‹                         技能详情             ✎  编辑  │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  [技能定义] [使用条件]                                     │
│  [描述]                                                    │
│  [SKILL.md 正文]                                           │
└────────────────────────────────────────────────────────────┘
```

## 详情页布局规范

适用范围：任务详情、技能详情、Gateway 详情等实体详情页。

- 打开方式：从列表卡片点击进入整页覆盖式详情页，不使用弹窗。
- 顶部：使用标准 AppBar。
- 第一屏内容：直接展示主体卡片，不额外增加大标题说明区。
- 主体：优先使用卡片分组展示元数据、状态、描述和正文。
- 长文本：使用可选择文本区域；代码或 Markdown 正文使用等宽字体。
- 操作：编辑、保存、创建等主动作放 AppBar；禁用、删除等危险动作放详情内容区或独立危险区。

## 可操作元素颜色规范

- 可操作的按钮、文字按钮、操作图标统一使用主题主色绿色，即 `colorScheme.primary`。
- 图标和文字同时出现时，图标与文字必须同色，例如 `编辑图标 + 编辑` 都使用绿色。
- 纯图标按钮可操作时也使用绿色，并通过 tooltip / semantics 说明动作。
- 不可操作或禁用状态使用 disabled 灰色，不使用绿色，避免误导用户可以点击。
- 危险操作使用 `colorScheme.error`，但必须配合确认弹窗或危险区说明，不使用绿色。
- 非操作性的说明文字、路径、状态辅助信息使用 `onSurfaceVariant` 或弱化灰色。
