# Changelog

## Unreleased

## v1.4.1 — 2026-05-27

### 新增

- 新增统一的 `CitationRenderer`：列表、详情、预览和插件刷新统一走 citeproc-js，减少 App 与 Word/WPS 插件之间的 CSL 输出差异。
- 新增 CSL 字段完整性诊断与“库体检”视图，可快速查看未补全的关键引用字段、验证状态和元数据来源分布。
- Word 插件支持 CSL cite-item 选项（locator、label、prefix、suffix、suppress-author），并在 note/footnote 样式下生成真正的脚注引文。

### 改进

- 增强 DOI、ISBN、ISSN、PMID、PMCID、arXiv 等标识符归一化，提升去重、CSL 输出和 DOI 内容协商路径的一致性。
- 批量导入与保存引用时返回更明确的新增、合并和更新结果，便于 UI 给出可解释的导入反馈。
- DOCX 刷新可读取脚注中的 SwiftLib 引文，并从 Custom XML 回填 cite-item 选项，降低文档来回编辑时定位页码/前后缀丢失的风险。
- CNKI 元数据刷新改为支持远程 selector 热更新，并以详情页解析为主，补齐搜索结果页可能缺失的卷、期、页码等字段。
- 维普检索解析会从出版信息行读取年份、期号和页码，避免把标题里的年份范围误当作出版年。

### 修复

- 修复 `swift run SwiftLib` 开发运行时 Sparkle 启动路径可能干扰调试的问题。
- 修复 SwiftPM 将 citation JSON fixture 当作未处理资源的警告。
- 修复 CSL golden snapshot 测试因样式切换顺序导致 citeproc engine 反复重建、运行时间异常的问题。

## v1.4.0 — 2026-05-18

### 新增

- 新增工作区（Workspace）模型：支持 all、manual、smart、hybrid 四种类型，持久化记录 sidebar 选区、搜索文本、列可见性及布局快照，可同时维护多个研究上下文。
- 新增万方数据与维普（VIP）期刊平台浏览器检索通道，作为 CNKI 的平行中文期刊元数据来源，支持候选结果排序与相似度过滤。
- CLI 新增三个 DOCX 命令：`refresh-docx`（刷新 .docx 引文编号与参考文献表）、`docx-audit`（检查引文与文献库一致性）、`prune-unused`（按 .docx 正文引用裁剪文献库未使用条目）。
- Word 插件新增简体中文 CSL 语言包（zh-CN），补齐中英混排引文的术语、日期格式与标点输出。
- 新增 `HiddenWKWebViewMediaGuard`：为后台隐藏 WKWebView 统一注入媒体静音与自动播放拦截脚本，防止意外触发摄像头/麦克风权限弹窗。

### 清理

- 重构元数据管线目录：Core metadata 服务从 `SwiftLibCore/Services/` 迁入专用 `SwiftLibCore/Metadata/`；`MetadataFetcher` 拆为 facade + 11 个 source/transport extension，`MetadataResolution` 拆为 facade + 5 个 decision/text extension；数据库入口 `AppDatabase` 拆为 10 个 domain extension。
- 重构 App target 目录结构：建立 `ViewModels/`、`Views/Readers/`、`Windowing/AIChat/`、`Navigation/`、`Search/`、`DesignSystem/`、`UIInfrastructure/`、`Updates/` 专用目录；CNKI 服务拆为 6 个 provider extension 归入 `Services/CNKI/`；`ChineseMetadata*` 从 App Services 迁入 Core Metadata。
- AI 助手 DOM 选择器升级至 v11（2026-05-14）：重新探针验证 ChatGPT、DeepSeek、豆包、Kimi 四项服务；ChatGPT 新增对未登录弹窗（`modal-no-auth-login`）的处理说明。

## v1.3.0 — 2026-04-29

### 新增

- 新增 OCR Markdown 连续翻译：可通过现有 AI 助手窗口分批翻译整篇 OCR 文档，并生成原文 + 小字译文的双语 Markdown。
- 新增可定制 OCR 翻译 Prompt，并支持对 AI 返回的 JSON、代码块 JSON、标签式译文和纯文本单段译文进行宽容解析。
- 新增 JSON site adapter runtime 与内置适配器，覆盖 CrossRef、OpenAlex、Semantic Scholar、Google Books、Open Library、豆瓣读书等来源。
- 新增百度学术 fallback、CNKI 导出解析和候选验证窗口，中文文献在 CNKI 无结果或不明确时可继续补救。
- 新增持久化元数据缓存、主机限速、熔断、并发请求合并和字段级合并服务，提升批量导入稳定性。

### 改进

- 重构 MetadataResolver 为路由、标识符、候选、CNKI、刷新等分层模块，降低单文件复杂度。
- 优化 AI 助手发送与回复抓取逻辑，增加回复稳定性跟踪，避免模型停顿时过早抓取未完成内容。
- 优化 OCR Markdown 表格、上下标和 HTML 片段渲染，减少扫描版论文中的版式破碎。
- 优化待确认元数据窗口，使用平面化透明标题栏和更紧凑的候选卡片布局。
- 优化右侧标注/笔记侧边栏空间利用，并移除卡片中不必要的细线分割。
- 优化 Word 插件本地服务与任务窗格交互，降低文档扫描和引用刷新时的等待感。

### 修复

- 修复 DOI 提取时会把原始大写校验字符强制转为小写的问题；显示和存储保留原始大小写，请求与缓存仍使用规范化 DOI。
- 修复 AI 回复还没完成就被当作最终 JSON 抓取时导致“没有合法 JSON”的问题。
- 修复部分 AI 网页输入框 selector 改版后注入失败的问题，并补充页面状态诊断。

### 清理

- 移除旧的内置 Node/Zotero translation backend，翻译能力改为复用现有 AI 助手窗口。

## v1.2.1 — 2026-04-17

### 修复

- 修复 AI 助手在未登录、页面仍在加载、发送按钮不可用或页面脚本卡住时可能一直转圈的问题；现在会主动诊断页面状态并给出明确提示。
- 修复 AI 助手在页面加载失败或 Web 内容进程终止后缺少可见反馈的问题；现在窗口顶部会显示加载失败或操作失败状态。

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
