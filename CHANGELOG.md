# Changelog

## Unreleased

## v1.2.0 — 2026-04-17

### 新增

- 新增 AI 助手独立窗口，支持 ChatGPT、豆包、Kimi、DeepSeek 多服务切换。
- 新增基于 DOM 选择器配置的 AI 输入注入与回复抓取能力，可直接从阅读器选区发起翻译或问答。
- 新增 PDF OCR 能力，支持通过 PaddleOCR 将扫描版 PDF 识别为 Markdown，并在阅读器中直接查看结果。
- 新增正式的设置窗口，集中管理通用选项、插件安装状态和 AI 服务配置。
- 新增 AI DOM 选择器远程配置服务，支持从 GitHub 拉取最新选择器定义并缓存到本地。

### 改进

- 重构文献列表加载链路，改为轻量行模型、总数观察和分页加载，降低大库场景下的内存与刷新成本。
- 优化 CNKI 页面解析与检查节奏，减少无效等待，并通过复用隐藏 WebView 降低解析开销。
- 为翻译后端预热启动、Word/WPS 插件服务、OCR 调用等路径补齐更清晰的运行时边界。
- 将 CLI、Word/WPS 插件和主应用的若干版本化发布入口整理为更一致的发布流程。

### 修复

- 修复数据库初始化失败后“提示可继续、实际后续崩溃”的问题；现在会明确降级到临时内存数据库会话。
- 修复文献列表分页在滚动触发时可能重复追加相同页面数据的问题。
- 修复翻译后端握手与关闭路径中的 Swift 并发告警，避免后续 Swift 6 模式下升级为硬错误。
- 修复 OCR Token 明文存储在 `UserDefaults` 的问题，改为迁移并存储到系统 Keychain。

### 安全

- 为 Word / WPS 本地 HTTP 服务增加 bearer token 鉴权，并收紧 CORS 允许范围。
- 为引用文档渲染接口增加结果缓存失效机制，降低重复请求时的暴露面与无效计算。

## v1.1.1 — 2026-04-13

### 修复

- 修复 CLI 工具安装到 /usr/local/bin 时因权限不足直接失败的问题；现在会在需要时自动弹出 macOS 管理员密码窗口完成安装。
- 修复 CLI 工具卸载在提权安装后可能无法删除的问题；现在会在需要时同样请求管理员授权。

### 兼容性

- 补齐缺失的 onboarding 兼容层，恢复当前工作区的可编译状态，避免热修复版本被无关残留代码阻塞。

## v1.1.0 — 2026-04-12

### 新增

- 增加 WPS Office 插件安装器、资源打包与任务窗格支持。
- 增加 Sparkle 自动更新接入、appcast 生成脚本和 GitHub Pages 发布流程。
- 增加阅读器操作条自适应布局与对应测试。

### 改进

- 重做 PDF / 网页阅读器的悬浮操作条布局与窗口默认尺寸。
- 优化标注侧边栏和网页标注卡片的悬停交互、完整笔记预览与滚动稳定性。
- 引用渲染支持按需跳过 bibliography，并降低 JSContext 池上限以控制内存。

### 清理

- 移除尚未定稿的新手引导实现。
- 删除旧的阅读器实现说明文档和 `PROMO.md`。

### WPS 插件（macOS 任务窗格）

#### 修复

- **任务窗格冻结**：将引文样式下拉菜单从原生 `<select>` 替换为自定义 HTML 菜单（button + listbox），绕过 WPS macOS 宿主对原生下拉的处理导致 WebView 冻结的问题。原生 `<select>` 保留为隐藏的状态存储，不再渲染。

- **插入引文后上角标溢出**：在 `refreshAllCitations` 最终块中新增 `WPSDocument.resetCaretSuperscript()`，通过 COM 接口强制将光标处的 `Font.Superscript` 置为 `false`；完成后通过系统事件触发一次隐式焦点往返（`System Events` → WPS），使 WPS 重新从光标处读取字符格式，从而保证插入引文后直接输入的文字为正文格式而非上角标。

- **插入引文后焦点跳回搜索框**：移除 `requestSearchFocus()`（原在插入成功后经 80ms 定时器将焦点移至任务窗格搜索输入框）。COM 书签写入操作本身在 WPS 进程内执行，光标自然停留在文档中，无需额外焦点操作。

- **样式切换空操作防抖**：`onStyleChange()` 增加提前返回判断——若新样式与当前样式相同，则跳过所有刷新与焦点操作。

#### 新增

- `WPSDocument.resetCaretSuperscript()`：对折叠光标处显式清除上下标格式，防止后续输入继承引文的上角标样式。

- `triggerFocusBounce()`：通用焦点往返辅助函数（取代原仅供样式切换使用的 `triggerFocusBounceForStyleSwitch()`），目前仅在插入引文成功后调用。

#### 清理

- 移除 `requestSearchFocus()` 函数及其所有调用点。

---

### 服务器（`WordAddinServer.swift`）

#### 新增

- **`POST /api/wps/focus-bounce`**：焦点往返接口。通过 `osascript` 内联脚本短暂激活 macOS `System Events`（后台守护进程，无可见界面），再立即重新激活 WPS，触发 WPS 文档区域重新获得焦点并刷新光标字符格式。

- **`POST /api/perf-log`**：接收 WPS 插件端发送的性能日志行，打印到服务器标准输出，便于开发调试。

- **`/wps/*` 静态文件路由**：`/wps/foo.js` 映射到 `Resources/WPSAddin/foo.js`，支持 WPS 插件资源的独立路径空间。

- **`focusBounceQueue`**：专用 `DispatchQueue`，隔离焦点往返的 `osascript` 进程调用，避免阻塞主服务器队列。

#### 改进

- **`POST /api/render-document`**：新增 `includeBibliography` 参数（默认 `true`），允许调用方跳过参考文献渲染，减少仅需刷新引文时的计算量。

- **`POST /api/render-document`**：当 `citations` 为空时提前返回空响应，避免无意义的引擎调用。

- `Bundle` 扩展改为 `internal`（去掉 `private`），供测试目标访问。

---

## v1.0.0 — 2026-03-xx

初始开源发布。
