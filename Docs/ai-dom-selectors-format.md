# AI DOM Selectors 热更新格式说明

本文档说明 SwiftLib AI 聊天窗口的 DOM 选择器热更新链路，以及本地缓存文件和远端 GitHub 文件需要遵循的 JSON 格式。

## 1. 当前接入方式

- 默认远端 URL：

  https://raw.githubusercontent.com/NickHood1984/SwiftLib/main/Sources/SwiftLib/Resources/ai-dom-selectors.json

- 加载优先级：

  1. 本地缓存文件 `~/Library/Application Support/SwiftLib/ai-dom-selectors.json`
  2. App 内置文件 `Sources/SwiftLib/Resources/ai-dom-selectors.json`

- 更新时机：

  - AI 聊天窗口打开时，如果距离上次成功更新超过 24 小时，会自动请求远端。
  - 工具栏刷新按钮会立即请求远端。

- 覆盖规则：

  - 远端 JSON 解码成功后才会写入本地缓存。
  - `services` 不能为空。
  - 远端 `version` 不能低于当前本地配置。
  - 如果 `version` 相同，则 `lastUpdated` 不能早于当前本地配置。

## 2. 本地文件和远端文件的关系

本地缓存文件和远端 GitHub 文件使用完全相同的 JSON 结构。

- 如果你手工修改本地缓存文件，格式必须与远端一致。
- 如果远端更新成功，本地缓存文件会被覆盖。
- 如果远端不可用，SwiftLib 会继续使用本地缓存；如果本地缓存也没有，则回退到 App 内置文件。

## 3. 根对象格式

```json
{
  "version": 3,
  "lastUpdated": "2026-04-13",
  "services": [
    {
      "id": "chatgpt",
      "name": "ChatGPT",
      "urlPattern": "chatgpt.com",
      "inputSelector": "#prompt-textarea",
      "sendSelector": "button[data-testid='send-button']",
      "responseSelector": "div.agent-turn",
      "contentSelector": "div.markdown",
      "streamingSelector": "div[class*='stream']",
      "notes": "已验证 2026-04-13"
    }
  ]
}
```

字段说明：

- `version`
  - 整数。
  - 每次远端规则发生实质变化时递增。
  - 不要回退版本号，否则会被 SwiftLib 忽略。

- `lastUpdated`
  - 建议使用 `YYYY-MM-DD`。
  - 也兼容 ISO 8601 时间格式，例如 `2026-04-14T12:30:00Z`。
  - 当 `version` 相同时，SwiftLib 会用它判断配置是否比本地更新。

- `services`
  - 数组，至少要有一个元素。
  - 每个元素代表一个 AI 网站的 DOM 规则。

## 4. service 对象格式

每个 `service` 必须包含以下字段：

```json
{
  "id": "chatgpt",
  "name": "ChatGPT",
  "urlPattern": "chatgpt.com",
  "inputSelector": "#prompt-textarea",
  "sendSelector": "button[data-testid='send-button']",
  "responseSelector": "div.agent-turn",
  "contentSelector": "div.markdown",
  "streamingSelector": "div[class*='stream']",
  "notes": "可选备注"
}
```

字段说明：

- `id`
  - 稳定的机器可读标识。
  - 建议使用小写英文，例如 `chatgpt`、`kimi`、`doubao`。

- `name`
  - 给 UI 或调试日志看的显示名称。

- `urlPattern`
  - 用来匹配当前网页 URL 的子串。
  - SwiftLib 会把当前 URL 转成小写后做 `contains` 匹配。
  - 例如 `chatgpt.com`、`chat.deepseek.com`、`kimi`。

- `inputSelector`
  - 输入框的 CSS 选择器。
  - 支持 `textarea`、`input`、`contenteditable` 容器。

- `sendSelector`
  - 发送动作的定义。
  - 有两种合法写法：
    - CSS 选择器：点击发送按钮。
    - `Enter`：模拟按下回车发送。
  - 如果写成空字符串 `""`，SwiftLib 也会按 `Enter` 处理。

- `responseSelector`
  - 每一条 AI 回复外层节点的 CSS 选择器。
  - SwiftLib 通过它统计回复数量，并取最后一条作为最新结果。

- `contentSelector`
  - 回复内容节点的 CSS 选择器。
  - 会在最后一条 `responseSelector` 节点内部查找。
  - 如果写成空字符串 `""`，SwiftLib 会直接把 `responseSelector` 节点本身当成内容节点。

- `streamingSelector`
  - 正在生成中的加载指示器 CSS 选择器。
  - 如果非空，SwiftLib 会在这个节点消失后再读取结果。
  - 如果为空字符串 `""`，SwiftLib 会退回到“文本稳定一段时间后认为完成”的策略。

- `notes`
  - 可选备注。
  - 可以写验证日期、网站特殊说明、已知限制等。

## 5. 维护建议

- 新增或修改规则时：
  - 先在本地内置文件 `Sources/SwiftLib/Resources/ai-dom-selectors.json` 验证。
  - 验证通过后再同步到远端文件。

- 推荐操作顺序：
  1. 修改 `services` 对应条目。
  2. 更新 `lastUpdated`。
  3. 如有实质变更，递增 `version`。
  4. 提交并推送到 GitHub 主分支。

- 不建议：
  - 把 `services` 发成空数组。
  - 降低 `version`。
  - 随意更改 `id`，否则会给后续排查带来不必要噪音。

## 6. 一个最小可用示例

```json
{
  "version": 4,
  "lastUpdated": "2026-04-14",
  "services": [
    {
      "id": "example-ai",
      "name": "Example AI",
      "urlPattern": "example.com/chat",
      "inputSelector": "textarea",
      "sendSelector": "Enter",
      "responseSelector": "div.message.assistant",
      "contentSelector": "div.markdown-body",
      "streamingSelector": "div.generating",
      "notes": "演示用配置"
    }
  ]
}
```