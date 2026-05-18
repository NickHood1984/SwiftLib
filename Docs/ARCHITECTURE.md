# SwiftLib Architecture

这份文档描述当前项目的目标框架。它不是功能说明，而是给开发者和 agent 判断“代码应该放哪、依赖应该怎么流动、改动应该验证什么”的结构说明。

## 总体原则

SwiftLib 的架构按 target 分层、按能力归位：

```text
SwiftLib App target
    macOS UI / WebKit / PDF reader / Office local server / feature orchestration
            |
            v
SwiftLibCore library target
    domain models / database / metadata APIs / adapters / citation / import-export
            ^
            |
swiftlib-cli executable
    command-line surface, reusing Core instead of reimplementing business logic
```

依赖方向只能是：

- `SwiftLib` -> `SwiftLibCore`
- `SwiftLibCLI` -> `SwiftLibCore`
- `SwiftLibCore` 不依赖 `SwiftLib`

## Target Responsibilities

### `Sources/SwiftLibCore`

Core 是可测试、可复用、尽量不含桌面 UI 的业务内核。

- `Models/`：持久化模型和值对象。
- `Database/`：`AppDatabase` 入口、migrations、shared storage、reference persistence/query/support、metadata persistence、collection/workspace/tag/annotation CRUD 与 observers。新增数据库 API 必须进入对应 `AppDatabase+*.swift` 文件，不再塞回入口文件。
- `Metadata/`：metadata API、路由规划、验证、字段级合并、并发抓取、缓存、限速、熔断和共享网络 client；`MetadataFetcher` 按 upstream/source 拆到 `MetadataFetcher+*.swift`，`MetadataResolution` 按 types/seed/merge/enrichment/routing/candidates/text 拆到对应 extension。
- `Services/`：导入导出、PDF/DOCX、YouTube/transcript 等不属于 metadata pipeline 的核心服务。
- `Adapters/`：JSON site adapter 定义、运行时、注册表，以及 app 注入 WebView 执行器所需的协议。
- `Citation/`：CSL、citeproc-js、Word citation rendering。
- `Resources/`：Core 运行需要的 CSL、adapter、Readability/Clipper、Word/WPS 插件共享资源。

Core 允许的 UI 相关例外是已有平台库能力，例如 `PDFService` 使用 PDFKit、`CiteprocJSCoreEngine` 使用 JavaScriptCore。不要把 SwiftUI/AppKit/WKWebView 流程放进 Core。

### `Sources/SwiftLib`

App target 是 macOS 桌面壳和需要用户会话的编排层。

- `SwiftLibApp.swift`：应用入口、Scene、启动期全局服务注册。
- `Views/`：SwiftUI 视图和与视图强绑定的小型组件。
- `Views/Readers/`：PDF/Web reader shell、toolbar、PDFKit/WKWebView bridge、OCR Markdown view、YouTube inline header 等 reader 视图层。
- `ViewModels/`：App/UI 状态编排、数据库 observer 订阅、用户操作到 Core service 的桥接。
- `ViewModels/Readers/`：PDF/Web reader 状态、annotation 操作、live-readable、YouTube transcript、HTML rendering/cleanup 等 reader ViewModel extension。
- `Windowing/`：NSWindow/NSPanel 生命周期、独立窗口、浮动验证面板和窗口共享 manager。
- `Windowing/AIChat/`：AI chat window manager、DOM automation、JS payload、错误映射、NSPanel factory、WKWebView bridge、host/status view 和通知常量。
- `Navigation/`：sidebar selection、workspace 布局快照和导航状态映射。
- `Search/`：App 内搜索语法解析和搜索 UI 支撑类型。
- `DesignSystem/`：设计 token、字体/间距/圆角、通用按钮样式。
- `UIInfrastructure/`：跨视图复用的滚动条、布局、hover tracking、reader action bar 计算等 UI 基础设施。
- `Services/`：App-only 服务，尤其是 WKWebView、AI 页面、百度学术、OCR 翻译编排。
- `Services/CNKI/`：CNKI/WKWebView 登录态、搜索、详情解析、导出 fallback、页面验证和 CNKI 注入脚本。
- `ReaderExtraction/`：在线正文提取服务流水线；不放 reader SwiftUI、toolbar 或 ViewModel。
- `Server/`：Word/WPS 本地服务与 manifest 安装器。
- `Helpers/`：Keychain、OpenPanel、Markdown HTML、NoteEditorPool、CLI 安装器等难以归入更专门目录的系统/工具辅助能力。
- `Updates/`：Sparkle 更新 UI 和 updater driver。
- `Resources/`：App 注入脚本、selector、图片和 HTML 资源。

App target 根目录应该尽量只保留应用入口、全局偏好和 entitlement。跨多个文件的功能模块优先进入明确子目录。`Views/` 不是所有 App 代码的兜底目录：reader bridge/toolbar/OCR/YouTube 子视图进入 `Views/Readers`，reader 状态进入 `ViewModels/Readers`，CNKI browser flow 进入 `Services/CNKI`，AI chat window lifecycle/DOM automation/WKWebView bridge/host view 进入 `Windowing/AIChat`，AI selector/diagnostics service 仍在 `Services/`，窗口、搜索、导航、设计系统和 UI 基础设施要分别进入上面的专用目录。

### `Sources/SwiftLibCLI`

CLI 只负责命令行接口。

- 参数解析、stdout/stderr、JSON DTO、CLI-only timeout/progress 放这里。
- 数据库、metadata、citation、DOCX、import/export 逻辑放 Core 后复用。
- 高风险命令需要显式 flag 或确认机制。

## Metadata Pipeline

元数据是项目核心框架之一，按以下职责拆分：

```text
User input / PDF seed / URL
        |
        v
MetadataResolver (App orchestration)
        |
        v
MetadataRoutePlanner (route decision)
        |
        v
ParallelSourceFetcher / CNKI provider / web metadata extractor
        |
        v
FieldLevelMerger + MetadataVerifier
        |
        v
AppDatabase.persistMetadataResolution
```

关键约束：

- 强标识符优先：DOI、PMID、arXiv、ISBN。
- 中文期刊/学位论文可以走 CNKI 浏览器流程。
- 中文图书、ISBN、book-like seed 不应误走中文期刊 fallback。
- 弱证据进入 candidate/pending，不静默写成 verified。
- 新 source 要同时考虑 route、source enum、evidence、merge priority、cache/rate limit、tests。
- `MetadataFetcher.swift` 只作为 facade；identifier、transport 和各 upstream provider/helper 放对应 `MetadataFetcher+*.swift`。
- `MetadataResolution.swift` 只作为 facade；seed、merge、enrichment、routing、candidate scoring 和 text helper 放对应 `MetadataResolution+*.swift`。

## Database Change Checklist

改持久化字段或模型时，必须检查：

- model Codable/GRDB 映射和默认值。
- migration 是否只追加、不破坏用户库。
- insert/update/fetch/list row/observer/FTS。
- metadata evidence/intake、dedup、verification status。
- CSL JSON、citation renderer、Word/WPS 插件协议。
- CLI DTO、import/export、BibTeX/RIS。
- in-memory database tests 和相关 integration tests。

## App Organization Roadmap

目前项目总体分层是合理的，但还有几个渐进优化方向：

1. 已建立 `Database/AppDatabase+*.swift` 分层；后续新增数据库能力必须按 persistence/query/support/migration/domain extension 归位。
2. 已建立 `ViewModels/`、`ViewModels/Readers/`、`Views/Readers/`、`Services/CNKI/`、`Windowing/`、`Navigation/`、`Search/`、`DesignSystem/`、`UIInfrastructure/`、`Updates/`；新 App 代码应优先归入这些目录，而不是继续扩大根 `Views/`、单个大 service 或泛化 `Helpers/`。
3. App target 根目录保持薄入口；新功能不要继续平铺到根目录。
4. metadata source 优先 adapter 化；Core metadata pipeline 相关代码放 `SwiftLibCore/Metadata/`，`MetadataFetcher` 新逻辑按 source extension 归位，只有 adapter runtime 覆盖不了时才写 Swift 特化逻辑。
5. `AIChatWindowManager` 已拆到 `Windowing/AIChat/`；新增 AI chat window lifecycle、DOM 注入/发送/轮询、JS payload、WKWebView bridge、host/status view 或 notification helper 时放对应拆分文件，不要回到单个 manager 文件。
6. Word/WPS 插件协议变化要保持 Core renderer、server route、前端 JS、CLI DOCX 命令同步。

这些优化应当随业务改动小步完成，不做一次性大搬迁。
