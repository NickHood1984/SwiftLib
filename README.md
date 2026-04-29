# SwiftLib

**为中国学术研究者打造的 macOS 原生文献管理工具**

SwiftLib 是一款面向 macOS 的文献管理、PDF/网页阅读、OCR、AI 辅助翻译和 Word 引用工具。它把本地文献库、中文学术元数据抓取、PDF 标注、网页剪藏、CSL 引用渲染与 Office 插件串成一个尽量少打断研究节奏的桌面工作流。

## 功能亮点

- **多源元数据管线**：DOI / PMID / arXiv / ISBN / 标题 / CNKI 链接统一入口，支持 CrossRef、OpenAlex、Semantic Scholar、Open Library、Google Books、豆瓣读书、CNKI 与百度学术回退。
- **站点适配器系统**：内置 JSON 驱动的 site adapters，可扩展网页元数据提取规则，并支持远程配置缓存。
- **OCR 连续翻译**：扫描版 PDF 可 OCR 为 Markdown，并通过现有 AI 助手窗口分批连续翻译为中英双语 Markdown。
- **PDF + 网页双阅读器**：PDFKit 原生 PDF 阅读器与 Defuddle / Readability 网页正文提取共用标注体验。
- **Word 插件**：本地 HTTP 服务驱动 Word 引用插入、参考文献生成和全文刷新，无需云端同步。
- **CLI 自动化**：提供搜索、导入、导出、引用生成、DOCX 标记等命令，支持脚本化工作流。
- **Sparkle 自动更新**：GitHub Release + appcast 发布流程，可分发 DMG 并生成增量更新信息。

## 功能详述

### 文献管理

- 支持期刊论文、图书、学位论文、会议论文、报告、专利、标准、网页、视频等结构化类型。
- 收藏夹支持层级组织，标签支持颜色和多对多关联。
- SQLite FTS5 全文搜索索引标题、作者、期刊、摘要、笔记、DOI 等字段。
- 高级搜索语法示例：`author:Smith year:2020-2024 journal:Nature type:journalArticle`。
- 文献详情页显示来源、标识符、期刊分区、URL、摘要和本地元数据状态。

### 元数据获取与验证

SwiftLib 现在采用路由规划 + 多源并发 + 字段级合并的元数据管线：

- **标识符优先**：DOI、PMID、arXiv、ISBN 会优先走对应权威源。
- **标题检索**：无强标识符时并行查询 OpenAlex、Semantic Scholar、图书源等，并在发现 DOI 后自动补抓 CrossRef。
- **中文文献**：中文期刊/学位论文优先走 CNKI 浏览器上下文；CNKI 无结果、低分或受阻时可回退百度学术。
- **图书场景**：中文图书和 ISBN 场景会避开不合适的 CNKI 期刊流程，优先走图书源。
- **站点适配器**：CrossRef、OpenAlex、Semantic Scholar、Google Books、Open Library、豆瓣读书等可通过 adapter schema 描述提取规则。
- **可靠性**：内存缓存 + SQLite 持久缓存、请求合并、主机限速、熔断和重试避免批量导入时重复打爆上游。
- **人工确认**：候选队列窗口可展开多候选、重试、删除或手动确认；验证证据会记录来源、规则和时间。

### PDF OCR 与连续翻译

- OCR 结果以 Markdown 展示，尽量保留标题、段落、列表、HTML 表格片段、上下标与数学内容。
- 连续翻译使用当前 AI 助手窗口，不额外捆绑翻译后端。
- 翻译会按上下文限制自动分批，支持自定义 Prompt 模板。
- 输出为双语 Markdown：原文段落后跟小字号中文译文，便于逐段校对论文。
- 解析器可容忍代码块 JSON、尾逗号、智能引号、部分截断和纯文本单段译文，降低 AI 回复格式波动带来的失败率。
- 翻译过程中会保存进度；失败或停止时已完成部分不会丢失。

### AI 助手窗口

- 支持 ChatGPT、豆包、Kimi、DeepSeek 等网页 AI 服务。
- DOM selector 配置可远程更新，避免网页改版后必须发新版客户端。
- 发送前会诊断未登录、页面仍在加载、输入框不可用、发送按钮不可用等状态。
- 回复抓取使用稳定性跟踪器，避免模型停顿时过早截断或把未完成 JSON 当成最终结果。

### PDF 与网页阅读

- PDF 阅读器支持目录、缩放、页码、标注侧边栏和文献信息侧边栏。
- 标注支持高亮、下划线和锚定笔记，并可在侧边栏中跳转与编辑。
- 网页阅读器支持剪藏正文和在线阅读两种模式。
- 网页正文提取优先 Defuddle，失败后回退 Readability；YouTube 页面可提取字幕转录。

### 引用与 Word 插件

- 内置 APA、MLA、Chicago、IEEE、Harvard、Vancouver、Nature 等引用样式。
- citeproc-js 通过 JavaScriptCore 嵌入运行，用于 CSL 参考文献渲染。
- Word 插件通过本地 `127.0.0.1:23858` 服务通信，并使用 bearer token 鉴权。
- 插件支持搜索文献库、插入引用、插入参考文献、刷新全文引用和 DOCX 引用标记。
- 服务器会缓存文档渲染结果，减少刷新引用时的重复计算。

### CLI

| 命令 | 功能 |
|------|------|
| `search` | 全文搜索，支持 JSON 输出 |
| `list` | 分页列出文献 |
| `get` | 按 ID 获取文献 |
| `add` / `update` / `delete` | 新增、修改、删除文献 |
| `move` | 移动文献到收藏夹 |
| `cite` | 按样式生成引用 |
| `import` / `export` | 批量导入导出 BibTeX / RIS / JSON |
| `collections` / `tags` | 管理收藏夹和标签 |
| `annotations` | 查询 PDF / 网页标注 |
| `styles` | 列出引用样式 |
| `tag-docx` | 为 `.docx` 中的引用附加 SwiftLib 元数据 |

## 技术栈

| 层级 | 技术 |
|------|------|
| UI | SwiftUI（macOS 14.0+） |
| 数据库 | GRDB + SQLite / FTS5 |
| PDF | PDFKit |
| 网页 | WebKit / WKWebView / JavaScript 注入 |
| Markdown | MarkdownView + 自研 OCR Markdown HTML 渲染补丁 |
| 元数据 | Site Adapter Runtime、CrossRef、OpenAlex、Semantic Scholar、CNKI、百度学术等 |
| 可靠性 | 持久缓存、请求合并、限速、熔断、字段级合并 |
| 引用 | citeproc-js + JavaScriptCore |
| Word 插件 | Network Framework HTTP 服务器 + Office JS |
| 更新 | Sparkle 2 |
| CLI | Swift Argument Parser |

## 系统要求

- macOS 14.0 Sonoma 或更高版本
- Apple Silicon 或 Intel Mac
- 首次打开未公证构建时，可能需要在系统设置中手动允许运行

## 构建

### 前置条件

- Xcode 15.0+
- Swift Package Manager 会自动拉取 Swift 依赖
- 如需生成 Sparkle appcast，需要本机已有 Sparkle 签名密钥

### 本地构建

```bash
git clone git@github.com:NickHood1984/SwiftLib.git
cd SwiftLib

# Debug DMG
./scripts/build-app.sh

# Release DMG
APP_VERSION=1.3.0 ./scripts/build-app.sh release

# 直接运行
swift run SwiftLib
```

构建产物位于 `build/`：

- `SwiftLib.app`
- `swiftlib-cli`
- `SwiftLib-<version>-Debug.dmg`
- `SwiftLib-<version>.dmg`

### Sparkle / GitHub Release 发布

```bash
# 首次生成 Sparkle 更新签名密钥
./scripts/sparkle-tools.sh generate-keys

# 构建 release 包
APP_VERSION=1.3.0 ./scripts/build-app.sh release

# 生成 GitHub Pages 使用的 appcast.xml
APP_VERSION=1.3.0 \
NOTES_SOURCE_FILE=Docs/releases/SwiftLib-1.3.0.md \
./scripts/publish-appcast.sh
```

发布时需要：

- 上传 `build/SwiftLib-1.3.0.dmg` 到 GitHub Release `v1.3.0`。
- 同步提交 `Docs/appcast.xml` 和 `Docs/releases/SwiftLib-1.3.0.md`，供 Sparkle 自动更新读取。
- 不需要再构建或捆绑旧版 Node/Zotero translation backend。

## 项目结构

```text
SwiftLib/
├── Sources/
│   ├── SwiftLib/              # macOS 主应用
│   │   ├── Views/             # SwiftUI 视图层
│   │   ├── Services/          # AI、OCR、CNKI、站点提取等应用服务
│   │   ├── Helpers/           # Markdown、滚动条、JSON 提取等工具
│   │   ├── ReaderExtraction/  # Defuddle / Readability 网页正文提取
│   │   ├── Server/            # Word/WPS 插件 HTTP 服务
│   │   └── Resources/         # JS、CSS、AI selector、site adapter 资源
│   ├── SwiftLibCore/          # 共享核心库
│   │   ├── Adapters/          # JSON site adapter runtime
│   │   ├── Models/            # Reference、Collection、Tag 等模型
│   │   ├── Database/          # GRDB 数据库层和迁移
│   │   ├── Citation/          # 引用格式化和 CSL 引擎
│   │   ├── Services/          # 元数据抓取、验证、缓存、导入导出
│   │   └── Resources/         # CSL、Word 插件资源、内置 adapters
│   ├── SwiftLibCLI/           # 命令行工具
│   └── SwiftLibProbe/         # 调试探针
├── Tests/                     # 单元测试与集成测试
├── Docs/                      # appcast、release notes、adapter 文档
├── scripts/                   # 构建、Sparkle、渲染辅助脚本
├── WordAddin/                 # Word 插件前端
├── WordAddinNpm/              # Word 插件构建辅助
└── Package.swift              # Swift Package 配置
```

## 开源致谢

| 组件 | 用途 |
|------|------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite ORM 与响应式查询 |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | macOS 自动更新 |
| [MarkdownView](https://github.com/Lakr233/MarkdownView) | Markdown 渲染 |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI 参数解析 |
| [citeproc-js](https://github.com/Juris-M/citeproc-js) | CSL 引用格式化 |
| [Readability.js](https://github.com/mozilla/readability) | 网页正文提取 |
| [Defuddle](https://github.com/kepano/defuddle) | 网页内容清洗与结构化提取 |

## 许可证

本项目为私有项目，暂未公开发布许可证。
