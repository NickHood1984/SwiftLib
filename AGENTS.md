# SwiftLib Agent Rules

本文件是 SwiftLib 仓库的接手规则。每次 agent 开工前先读它，再读 `Package.swift`、`Docs/ARCHITECTURE.md` 和与任务相关的源码/文档。若 README、旧文档和 `Package.swift` 冲突，以 `Package.swift` 与当前源码为准。

## 项目定位

SwiftLib 是面向中国学术研究者的 macOS 原生文献管理工具。核心工作流是：本地文献库、PDF/网页阅读、中文/英文元数据抓取与验证、OCR 翻译、CSL 引用渲染、Word/WPS 插件和 CLI 自动化。

当前包结构以 Swift Package 为准：

- `SwiftLibCore`：共享核心库。
- `SwiftLib`：macOS SwiftUI 应用。
- `swiftlib-cli`：命令行工具。
- `SwiftLibProbe`：构建时探针 target，用于隔离验证特定 Core API；仅供内部诊断使用，不包含业务逻辑，不要在此添加功能代码。

技术栈：Swift 5.9、macOS 14+、SwiftUI、GRDB/SQLite/FTS5、PDFKit、WebKit/WKWebView、JavaScriptCore/citeproc-js、Network Framework、Sparkle、Swift Argument Parser。

## 核心原则（每次接手必读，违反任何一条都算交付失败）

以下原则全部来自本项目踩过的真实事故，不是泛泛的最佳实践。改动任何代码前先对照一遍。

1. **数据真实性高于功能数量。** 不伪造置信度：候选评分必须反映真实证据强度，禁止人为下限/抬分（历史教训：万方/维普曾用 `max(titleScore, 0.45)`，垃圾结果以"45%"挤掉诚实评分的 CNKI 候选）。弱证据一律进人工确认队列，永远不要静默导入为 verified。
2. **永不挂起。** 每个 `CheckedContinuation` 必须保证在所有路径上都会 resume：用户操作、任务取消（用 `withTaskCancellationHandler` 包装）、外部回调缺席。WKWebView 的 delegate 回调（`didFinish` 等）不可完全信赖，等待它的代码必须配超时（历史教训：CNKI/百度人机验证等待不响应取消，导致"正在刷新元数据…"永久挂起；`HTMLLoadDelegate` 无超时曾卡死整条管线）。
3. **警惕 actor 重入。** actor 方法在 `await` 后，状态可能已被并发调用改写。时间戳、时隙、in-flight 标记这类状态必须在挂起**前**预占，不要 sleep 完再写（历史教训：`HostRateLimiter` 先 sleep 后更新时间戳，批量刷新时限速完全失效、成批 429）。
4. **对外部源既礼貌又设防。** 新增网络调用必须走 `NetworkClient.session` + `HostRateLimiter` + `HostCircuitBreaker`，并有超时；并行多源抓取不等最慢的源（单源软超时，见 `ParallelSourceFetcher`）。这些组件本身必须有单元测试。
5. **重构不丢链路。** 跨文件的调用链（尤其中文回退链：CNKI → 万方/维普 → 百度学术）必须有测试锁住存在性；README/CHANGELOG 承诺的行为就是合约（历史教训：v1.4.0 重构悄悄丢掉了百度学术回退的调用链，直到 v1.5.1 才发现）。
6. **中文数据不许被西文规则污染。** 中文作者名走 Han 感知解析（`MetadataResolution.structuredChineseAuthor`），禁止让 `AuthorName.parse` 把"张 三"拆成姓/名；少数民族姓名（含"·"）保持完整。中文标题、作者顺序、卷期页码不被英文源覆盖（参考 `ChineseMetadataConsensus` 的来源优先级规则）。
7. **用户数据神圣。** migration 只追加；不默认擦库；保存 reference 时保留去重、验证状态、evidence、PDF 路径和集合/标签关系；发布前必须验证上一个版本的真实数据能正常过渡（见"发布流程与升级兼容"）。
8. **改完就测，零覆盖不上线。** 新增或修改的管线组件必须带单元测试；跑与改动风险匹配的测试再交付，没跑要说明原因。

## 先做什么

1. 先运行 `git status --short`，确认已有未提交改动。不要回退、覆盖、格式化或清理用户已有改动。
2. 用 `rg` / `rg --files` 找入口和引用。不要先大范围猜测。
3. 读 `Package.swift` 确认 target、依赖和资源复制方式。
4. 读 `Docs/ARCHITECTURE.md` 确认 target 边界、metadata pipeline 和迁移路线。
5. 只读与任务直接相关的文件；如果需要理解架构，再读本文件列出的对应模块。
6. 浏览器打开、检查、自动化、接管、网页检索时，优先使用 `agent-browser` 技能。优先复用系统已有 Chrome；只有现有 Chrome 明确不可用时，才执行 `agent-browser install` 或下载额外浏览器。

## 分层框架

### 1. `Sources/SwiftLibCore`

Core 放跨 UI 复用的业务能力。默认不依赖 SwiftUI/AppKit/WebKit。

应该放在 Core 的内容：

- `Models/`：`Reference`、`Collection`、`Tag`、`Workspace`、metadata intake/evidence、PDF/Web annotation 等领域模型。
- `Database/`：`AppDatabase` 入口、GRDB migrations、shared storage、reference persistence/query/support、metadata persistence、collection/workspace/tag/annotation CRUD 与 observer。新增数据库 API 必须进入对应 `AppDatabase+*.swift` 文件。
- `Citation/`：CSL 解析、citeproc-js 桥接、Word 引用渲染、引用文本格式化。
- `Metadata/`：HTTP 元数据 API、路由规划、验证、字段合并、并发抓取、缓存、限速、熔断、共享网络 client；多源共识（`ChineseMetadataConsensus`）、中文字段合并策略（`ChineseMetadataMergePolicy`）等无 WebKit 依赖的中文元数据逻辑也放这里；`MetadataFetcher` 按 upstream/source 拆到 `MetadataFetcher+*.swift`，`MetadataResolution` 按 types/seed/merge/enrichment/routing/candidates/text 拆到对应 extension。
- `Services/`：导入导出、PDF 文本/元数据处理、DOCX 引用处理、YouTube/transcript 等非 metadata pipeline 核心服务。
- `Adapters/`：JSON site adapter schema/runtime/registry，以及 `WebViewAdapterExecutor` 协议。
- `Resources/`：内置 CSL、site adapters、Readability/Clipper 资源、Word/WPS 插件共享静态资源。
- `Utilities/`：跨 Core 内部复用的 Swift 基础扩展（如 `String+NilIfBlank`、`String+HTMLEntities`）；不放业务类型，不放任何 SwiftUI/AppKit 代码。

Core 的边界规则：

- 网络请求默认走 `NetworkClient.session`，不要随手加 `URLSession.shared`，除非该文件已有明确的特殊原因。
- 共享可变异步状态优先用 `actor`。在 actor 内并发请求，沿用 `ParallelSourceFetcher` 的 `withTaskGroup` 风格。
- UI、WKWebView 会话、NSPanel、AppKit 安装器等放到 `SwiftLib` target，不要塞进 Core。
- 已有例外要尊重：`PDFService` 可用 PDFKit，`CiteprocJSCoreEngine` 可用 JavaScriptCore，`AppDatabase` 可发布 Combine observer。

### 2. `Sources/SwiftLib`

App target 放 macOS UI、WebKit 会话、桌面集成和应用编排。

应该放在 App 的内容：

- `SwiftLibApp.swift`：应用入口、Scene、Sparkle、启动时全局服务注册。
- `Views/`：SwiftUI 视图、metadata queue、设置页、导入界面；不要放大型 ViewModel 或窗口 manager。
- `Views/Readers/`：PDF/Web reader shell、toolbar、PDFKit/WKWebView bridge、OCR Markdown view、YouTube inline header 等 reader 视图层。
- `ViewModels/`：App/UI 状态编排、数据库 observer、用户操作到 Core service 的桥接。
- `ViewModels/Readers/`：PDF/Web reader 状态、annotation 操作、live-readable、YouTube transcript、HTML rendering/cleanup 等 reader ViewModel extension。
- `Windowing/`：NSWindow/NSPanel 生命周期、独立窗口、浮动面板、共享窗口 manager。
- `Windowing/AIChat/`：AI chat window lifecycle、DOM 注入/发送/轮询、JS payload、错误映射、WKWebView bridge、host/status view 和通知常量；不要塞回单个 `AIChatWindowManager.swift`。
- `Navigation/`：sidebar selection、workspace 布局快照和导航状态映射。
- `Search/`：App 内搜索语法解析和搜索 UI 支撑类型。
- `DesignSystem/`：设计 token、字体/间距/圆角、通用按钮样式。
- `UIInfrastructure/`：跨视图复用的滚动条、布局、hover tracking、reader action bar 计算等 UI 基础设施。
- `Services/`：需要 WKWebView、登录态、AI 网页、百度学术浏览器流程、OCR 翻译编排的 app 级服务。
- `Services/CNKI/`：CNKI/WKWebView 登录态、搜索、详情解析、导出 fallback、页面验证和 CNKI 注入脚本；不要塞回单个大 service 文件。
- `ReaderExtraction/`：在线网页正文提取服务流程，围绕 WKWebView、Defuddle、Readability、YouTube fallback；不要混入 reader SwiftUI 或 toolbar。
- `Server/`：Word/WPS 插件本地 HTTP 服务和 manifest 安装器。
- `Helpers/`：Markdown HTML、Keychain、OpenPanel、NoteEditorPool、CLI 安装器等难以归类到更专门目录的系统/工具辅助能力。
- `Updates/`：Sparkle 更新 UI、updater driver 和更新相关面板。
- `Resources/`：App 专用 JS/CSS/selector/图片资源。

App 的边界规则：

- App target 根目录保持薄入口，原则上只放 `SwiftLibApp.swift`、全局偏好、entitlements 等顶层启动配置。跨多个类型的功能模块必须进入明确子目录。
- `Views/` 只作为视图目录，不再作为 App target 的杂物目录。新增状态、窗口、搜索、导航代码必须优先放进对应专用目录。
- `Helpers/` 只放难以归类的系统/工具辅助代码；设计系统和跨视图 UI 基础设施不得继续塞进 `Helpers/`。
- SwiftUI 视图只做展示与用户事件转发；数据库操作和业务流程放到 `LibraryViewModel` 或 service。
- WKWebView、窗口、AppKit delegate、sheet/panel 相关类型必须在主线程；已有文件多用 `@MainActor`，新增同类代码要跟随。
- UI 样式优先复用 `SLDesign`、`ModernButtonStyles`、`ElegantScrollerStyling`、已有 Reader/Sidebar/List 组件风格。
- 不做营销式首页，不加装饰性大渐变/大卡片。这个应用是研究工作台，界面要紧凑、清晰、可重复操作。

### 3. `Sources/SwiftLibCLI`

CLI 是 Core 的薄入口，不重新实现业务逻辑。

规则：

- 新命令放在 `SwiftLibCLI`，复用 `SwiftLibCore` 的模型、数据库、导入导出、引用和 DOCX 能力。
- 机器可读输出走 JSON；进度、warning、错误说明写 stderr。
- 删除、覆盖、批量变更等高风险命令必须有明确 flag 或交互保护。
- CLI 版本号和用户可见命令变化要同步测试。

### 4. `Tests`

测试按 target 分层：

- `Tests/SwiftLibCoreTests`：Core 模型、数据库、metadata、adapter、citation、DOCX 等。
- `Tests/SwiftLibTests`：App ViewModel、UI 辅助逻辑、WKWebView host、resolver app 编排。
- `Tests/SwiftLibCLITests`：CLI 命令行为。

数据库测试使用 `AppDatabase(DatabaseQueue(path: ":memory:"))`。不要让测试写用户真实 Application Support 数据库。

## 文件放置决策

按这个顺序决定新代码放哪里：

- 纯领域类型、解析、验证、合并、导入导出：放 `SwiftLibCore`。
- 需要 SwiftUI/AppKit/WebKit/PDF 阅读 UI/AI 网页登录态：放 `SwiftLib`。
- 命令行参数、stdout/stderr、shell 自动化入口：放 `SwiftLibCLI`。
- ViewModel：放 `Sources/SwiftLib/ViewModels`。
- Reader ViewModel：放 `Sources/SwiftLib/ViewModels/Readers`，按 PDF/Web 和 live-readable/transcript/rendering extension 拆分。
- Reader SwiftUI、toolbar、PDFKit/WKWebView bridge、OCR/YouTube 子视图：放 `Sources/SwiftLib/Views/Readers`。
- NSWindow/NSPanel manager：放 `Sources/SwiftLib/Windowing`。
- AI chat window 的窗口生命周期、DOM automation、WKWebView bridge、host view、status banner 和通知：放 `Sources/SwiftLib/Windowing/AIChat`；AI selector/diagnostics service 仍放 `Sources/SwiftLib/Services`。
- sidebar/navigation state：放 `Sources/SwiftLib/Navigation`。
- 搜索语法解析：放 `Sources/SwiftLib/Search`。
- 设计 token、按钮样式：放 `Sources/SwiftLib/DesignSystem`。
- 滚动条、布局、hover tracking、reader action bar、可复用控件（如 `OverlayScrollView`、`DraggableSegmentedControl`）、加载动画（如 `NeonBreathingLoader`）等跨视图 UI 基础设施：放 `Sources/SwiftLib/UIInfrastructure`。
- 上游元数据源 JSON/HTML 抽取规则：优先放 `Sources/SwiftLibCore/Resources/adapters/*.json`，不要先硬编码 Swift 抓取。
- App 专用注入脚本或 selector：放 `Sources/SwiftLib/Resources`。
- CNKI browser flow、页面验证、搜索请求、详情解析、导出 fallback 和 CNKI 格式解析（如 `CNKIExportParser`）：放 `Sources/SwiftLib/Services/CNKI`。
- 中文元数据多源共识与字段合并策略（不依赖 WebKit）：放 `Sources/SwiftLibCore/Metadata`，参考 `ChineseMetadataConsensus`、`ChineseMetadataMergePolicy`。
- Core 内部跨文件复用的基础 Swift 扩展（非业务类型）：放 `Sources/SwiftLibCore/Utilities`。
- Word/WPS 插件共享资源：放 `Sources/SwiftLibCore/Resources/WordAddin` 或 `WPSAddin`；本地服务和安装器放 `Sources/SwiftLib/Server`。
- Sparkle 更新 UI/驱动：放 `Sources/SwiftLib/Updates`。
- Core metadata API、路由、验证、合并、缓存、限速、熔断和网络 client：放 `Sources/SwiftLibCore/Metadata`；`MetadataFetcher` 新 provider/helper 按 source 或 transport 职责进入 `MetadataFetcher+*.swift`，`MetadataResolution` 新 seed/merge/enrichment/routing/candidate/text helper 进入对应 `MetadataResolution+*.swift`。
- 数据库入口只放 `Sources/SwiftLibCore/Database/AppDatabase.swift`；migrations、shared storage、reference persistence/query/support、metadata persistence、collections、workspaces、tags、annotations 分别放对应 `AppDatabase+*.swift`。
- 构建、发布、canary、资源生成脚本：放 `scripts/`。
- 维护说明、schema、发布记录：放 `Docs/`。

不要随意新增顶层目录。已有 `tmp/`、`build/`、`.build/`、`.xcodebuild*`、`node_modules/` 属于临时或构建产物，除非任务明确要求，不要编辑、提交或依赖它们。

## 渐进式改造路线

架构优化必须小步做，避免在大量业务改动同时做全仓搬迁。

- 优先搬未修改、引用面小、target 不变的文件；搬迁前用 `git status --short <path>` 确认没有用户改动。
- 每次只确立一个清晰边界，例如 `Updates/`、`ViewModels/`、`Windowing/`、`Navigation/`、`Search/`、`DesignSystem/`、`UIInfrastructure/`、Reader 拆分、数据库 domain extension 拆分。
- 文件移动后不顺手改行为；行为改动和目录改造尽量分开提交。
- `AppDatabase.swift` 已是薄入口；后续不要把 CRUD、query、migration 或 persistence helper 加回入口文件。
- `PDFReaderView.swift` / `WebReaderView.swift` 已拆到 `Views/Readers` 与 `ViewModels/Readers`；后续不要把 ViewModel、PDFKit/WKWebView bridge、toolbar、OCR 或 YouTube 子视图塞回单个大 View 文件。
- `CNKIMetadataProvider` 已拆到 `Services/CNKI/`；后续不要把 search/detail/export/script/navigation helper 塞回一个大 provider 文件。
- `MetadataFetcher.swift` 已是薄 facade；后续不要把 identifier、transport、Crossref、OpenAlex、Semantic Scholar、PubMed、arXiv、ISBN/book 或 Douban helper 塞回单个 fetcher 文件。
- `MetadataResolution.swift` 已是薄 facade；后续不要把 public types、seed 构造、merge、enrichment、routing、candidate scoring 或 text helper 塞回单个 resolution 文件。
- `AIChatWindowManager` 已拆到 `Windowing/AIChat/`；后续不要把 DOM injection、polling、JS payload、WKWebView bridge、host view、window factory 或 notification helper 塞回单个 manager 文件。
- `Views/` 后续只继续保留真正的 SwiftUI 视图；发现非视图类型时优先归位到专用目录。
- `Helpers/` 后续继续收窄；能归为设计系统、UI 基础设施、服务、导航或搜索的文件不要留在 Helpers。
- `OverlayScrollView`、`DraggableSegmentedControl`、`NeonBreathingLoader` 已从 `Views/` 移入 `UIInfrastructure/`；后续同类跨视图复用控件直接放 `UIInfrastructure/`，不要放回 `Views/`。
- `CNKIExportParser` 已从 `Services/` 移入 `Services/CNKI/`；CNKI 相关解析文件不要散落在 `Services/` 根目录。
- `ChineseMetadataMergePolicy`、`ChineseMetadataConsensus` 已从 App `Services/` 移入 `SwiftLibCore/Metadata/`（均已加 `public`）；后续无 WebKit 依赖的中文元数据逻辑直接放 Core，不要留在 App。
- `SwiftLibCoreDebugLogging` 已从 `SwiftLibCore/` 根目录移入 `Utilities/`；Core 根目录只保留入口文件。
- `SwiftLibDebugLogging`（App 调试开关）已从 `Services/` 移入 `Helpers/`；调试工具类不属于服务目录。
- `HiddenWKWebViewMediaGuard` enum 已从 `Views/HiddenWKWebViewHost.swift` 拆出到 `Helpers/HiddenWKWebViewMediaGuard.swift`；`HiddenWKWebViewHost` 视图保留原文件。
- `FloatingProgressToast` 已从 `Views/ContentView.swift` 拆出到 `UIInfrastructure/`；后续同类复用 toast/banner 撤直放 `UIInfrastructure/`。
- `LibraryViewModel` 已按职责拆为 `LibraryViewModel+References.swift`、`LibraryViewModel+MetadataQueue.swift`、`LibraryViewModel+Collections.swift`、`LibraryViewModel+Workspaces.swift`、`LibraryViewModel+Import.swift`；主文件保留状态属性、观察、分页逻辑；后续新增 ViewModel 方法按这五个 extension 归位。
- `ContentView` 已按职责拆为 `ContentView+WorkspaceLayout.swift`、`ContentView+MetadataRefresh.swift`、`ContentView+ImportActions.swift`；主文件保留状态声明、居中块、toolbar、sheet、overlay 结构；后续同类操作方法按职责归入对应 extension 文件。

## 数据库和模型规则

修改 `Reference` 或其他持久化模型时，必须一起检查：

- `Sources/SwiftLibCore/Models/*.swift` 的 Codable/GRDB 映射、默认值、归一化字段。
- `Sources/SwiftLibCore/Database/AppDatabase+*.swift` 中对应的 migration、insert/update、fetch、list row、observer、FTS。
- `ReferenceListRow`、搜索过滤、去重逻辑、metadata evidence/intake 是否需要字段。
- `Reference+CSLJSON.swift`、citation formatter、Word renderer 是否需要暴露字段。
- CLI DTO、import/export、BibTeX/RIS/JSON 是否需要同步。
- Core tests 和 App/CLI tests 是否覆盖迁移、保存、查询、导出。

数据库规则：

- 不要在 DEBUG 下默认擦库。已有 `SWIFTLIB_RESET_DB_ON_SCHEMA_CHANGE=1` 是显式 opt-in。
- schema 变化只追加 migration，不改旧 migration 的语义，除非是在修复当前未发布 migration。
- 保存 reference 时要保留现有去重、verification status、evidence、PDF path、workspace/collection/tag 关系。
- FTS 字段变化要重建虚表并补测试。

## 元数据框架

元数据主线：

1. `MetadataResolver`（App target）负责入口编排、CNKI/WKWebView/browser fallback、人工确认入口。
2. `MetadataRoutePlanner` 判断 DOI/ISBN/PMID/arXiv/title/CNKI/book/journal 路由。
3. `ParallelSourceFetcher` 并发抓 CrossRef/OpenAlex/Semantic Scholar/PubMed/arXiv/ISBN 等。
4. `FieldLevelMerger` 做字段级优先级合并和 confidence score。
5. `MetadataVerifier` / `MetadataResolution` 产出 `verified`、`candidate`、`blocked`、`seedOnly`、`rejected`。
6. `AppDatabase.persistMetadataResolution` 保存 verified 或 pending intake/evidence。

规则：

- DOI/PMID/arXiv/ISBN 等强标识符优先。
- 中文期刊/学位论文可走 CNKI 浏览器上下文；中文图书或 ISBN/book-like seed 不要误走期刊 CNKI fallback。
- 无强标识符的英文/通用标题优先走并发 API 源，发现 DOI 后再补 CrossRef。
- 不能把弱证据直接静默导入为 verified；不满足规则时进入 candidate/pending，让用户确认。
- 新 metadata source 要定义 source enum、display name、证据 bundle、route planner 行为、合并优先级、缓存/限速策略和测试。
- Core metadata pipeline 文件归入 `Sources/SwiftLibCore/Metadata`；`MetadataFetcher` 保持 facade + source extension 分层，`MetadataResolution` 保持 facade + decision/text extension 分层；App 中需要 WKWebView/登录态的 CNKI browser flow 放 `Sources/SwiftLib/Services/CNKI`，其他 app-only metadata 编排仍留在 `Sources/SwiftLib/Services`。
- 调试日志使用 `SWIFTLIB_DEBUG_METADATA=1` / `SWIFTLIB_DEBUG_RUNTIME=1` / `SWIFTLIB_DEBUG_SQL=1`，不要长期保留无开关的 noisy print。

## Site Adapter 规则

适配器是元数据抓取的优先扩展点。

- 先读 `Docs/ADAPTERS_REPAIR.md`、`Docs/adapter-schema.json`，再改 `Sources/SwiftLibCore/Resources/adapters/*.json`。
- 只能使用 schema 里实现过的 `kind`、`transform`、`postProcess`、字段结构。不要发明运行时不支持的值。
- 修上游 schema 漂移时，优先追加新 path/regex/filter 值，保留旧规则作为 fallback。
- 修改 adapter 后 bump `schemaVersion`，必要时更新 canary expected。
- 真实网络验证用 `SWIFTLIB_CANARY=1 swift test --filter CanaryIntegrationTests`；普通单元测试不应依赖外网。
- 需要浏览站点结构时，优先使用 `agent-browser`，复用系统 Chrome。

## UI 和交互规则

- macOS 原生优先：SwiftUI + SF Symbols + 标准快捷键 + `.help()` + 可访问标签。
- 复杂窗口/reader/metadata queue 的状态放 ViewModel 或专门 manager，不把长流程塞进 `body`。
- 复用现有 compact table/sidebar/detail 三栏范式。新增主工作流要能键盘操作、批量处理、错误可恢复。
- 文字要短，面向研究工作，不写“功能介绍式”占位文案。
- 用户可见文案一律中文（按钮、提示、错误、候选字段、条目类型如“期刊论文”）；不要把 `title`/`Journal Article` 这类内部值直接显示给用户。开发者日志、调试输出可以英文。
- 同一界面不重复展示同一信息：上方已展示的字段（作者/期刊/摘要等）不要在下方卡片或附注里再罗列一遍；窗口标题不要与系统标题栏重复。
- 辅助窗口（待确认队列、设置类独立窗口）用 `.windowStyle(.hiddenTitleBar)`，标题只在内容区出现一次。
- 浮层类 UI（toast、消息条、通知卡片）统一用 `slOverlaySurface` 修饰符，不要各自手写背景/描边/阴影。
- 新按钮/卡片/浮层用现有 spacing、font、corner radius token；避免一页里多套视觉语言。
- 修改 PDF/Web reader 后，要检查选区 action bar、sidebar、annotation、滚动条和窗口尺寸。

## Word/WPS 插件规则

- 本地服务入口在 `Sources/SwiftLib/Server/WordAddinServer.swift`。
- Manifest 安装器在 `WordAddinInstaller.swift`、`WPSAddinInstaller.swift`。
- Office/WPS 前端资源在 `Sources/SwiftLibCore/Resources/WordAddin` 和 `WPSAddin`。
- 引用语义、CSL、DOCX 标记处理放 Core，不放 JS 里重复实现。
- 改插件协议时，同步 server route、前端 JS、CLI DOCX 命令、Core renderer/processor 和测试。
- 不直接改生成/打包产物，除非没有源文件或任务明确要求；如果必须改，要说明原因。

## 构建和验证

常用命令：

- `swift build`
- `swift test`
- `swift test --filter <TestName>`
- `swift run SwiftLib`
- `swift run swiftlib-cli --help`
- `./scripts/build-app.sh`
- `SWIFTLIB_CANARY=1 swift test --filter CanaryIntegrationTests`

验证选择：

- 纯模型/解析/数据库：跑相关 `SwiftLibCoreTests`。
- App ViewModel/UI 辅助逻辑：跑相关 `SwiftLibTests`。
- CLI 行为：跑 `SwiftLibCLITests` 或目标命令测试。
- Metadata API 或 adapter：先跑单元测试；真实上游验证只在明确需要时跑 canary。
- UI/reader/WebKit 改动：能自动化时用 `agent-browser` 或本地运行 app 检查；无法自动化时在交付说明里说清楚未验证范围。

如果网络、GUI、外部服务、证书或登录态导致验证不能跑，要明确说明阻塞原因和已完成的替代验证。

## 发布流程与升级兼容

版本号约定：只含改进/修复 → patch（如 v1.5.0 → v1.5.1）；含新增功能 → minor。开发期间用户可见的变化随手记入 `CHANGELOG.md` 的 `## Unreleased` 段落，发布时把该段落标题改为 `## vX.Y.Z — 日期`。

发布步骤（以 v1.5.1 实际流程为准）：

1. `swift build` + `swift test` 全绿；代码审查无遗留问题。
2. 写 `Docs/releases/SwiftLib-X.Y.Z.md` 发布说明（格式参考既有文件：重点更新 / 改进 / 验证）。
3. `APP_VERSION=X.Y.Z ./scripts/build-app.sh release` 生成 DMG（版本号默认取最近 tag，发布新版本时必须显式传 `APP_VERSION`）。
4. `APP_VERSION=X.Y.Z NOTES_SOURCE_FILE=Docs/releases/SwiftLib-X.Y.Z.md ./scripts/publish-appcast.sh` 更新 `Docs/appcast.xml`（需要钥匙串中的 Sparkle 私钥，账户 `com.swiftlib.app`）。
5. 单个 release commit（`feat: release vX.Y.Z`，包含 CHANGELOG、appcast、发布说明和代码），打 tag `vX.Y.Z`，push main 和 tag。
6. `gh release create vX.Y.Z` 上传 DMG，标题 `SwiftLib X.Y.Z`，notes 用发布说明文件；appcast 中引用的 `build/sparkle-archives/*.delta` 增量包必须一并上传，否则老版本 Sparkle 增量更新 404。
7. 验证 `https://nickhood1984.github.io/SwiftLib/Docs/appcast.xml` 已包含新版本条目。

升级兼容（发布前必查，这是数据真实性原则在发布环节的延伸）：

- 用上一个 release 版本产生的真实数据启动新构建，确认：GRDB migration 全部跑通且无数据丢失（reference 数量、验证状态、evidence、集合/标签/PDF 关系完整）；FTS 搜索可用；已导入的 CSL 样式仍能列出并正常渲染；UserDefaults 偏好未被重置。
- 任何改动落盘格式的版本（数据库 schema、CSL 样式存储、缓存目录、配置文件命名规则），必须显式检查旧文件的兼容路径，并在 CHANGELOG/发布说明中注明是否需要迁移（案例：v1.5.1 改了 CSL 落盘文件名规则，靠"查找按文件内容 `<id>` 而非文件名"才保住了对旧文件的兼容——这类检查不能靠运气，要主动做）。
- 条件允许时用上一版本安装包走一次 Sparkle 更新（含 delta），确认升级后数据完好。无法手工验证的项目，在交付说明里明确列出未验证范围。

## 代码风格

- 遵循现有 Swift 风格：小而明确的类型、`MARK:` 分段、早返回、清晰错误信息。
- 新公共 API 尽量 `Sendable`，异步边界标清 `@MainActor` 或 actor 隔离。
- 错误不要吞掉；用户可恢复的错误要进入 UI 状态或 pending queue，开发诊断走 OSLog/调试开关。
- 不做无关重构、全仓格式化、依赖升级或大规模文件搬迁。
- 新依赖必须先证明比现有 Foundation/GRDB/WebKit/PDFKit/ArgumentParser/MarkdownView/Sparkle 组合更合适。
- 保持资源复制方式与 `Package.swift` 一致；新增 resource 后确认 target resources 是否包含。

## 收尾规则

交付前检查：

1. `git diff --stat` 确认只改了任务相关文件。
2. 运行与改动风险匹配的测试/构建。
3. 如果没有跑测试，说明原因。
4. 用户可见的行为变化已记入 `CHANGELOG.md` 的 `## Unreleased` 段落。
5. 对照"核心原则"逐条自查本次改动，特别是：continuation 是否所有路径都 resume、actor 状态是否挂起前预占、落盘格式改动是否兼容旧数据。
6. 最终回复用简短中文说明改了什么、验证了什么、剩余风险是什么。
