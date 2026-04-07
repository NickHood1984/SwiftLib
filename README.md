# SwiftLib

**为中国学术研究者打造的 macOS 原生文献管理工具**

SwiftLib 是一款全功能学术文献管理应用，专为 macOS 平台原生开发。它深度集成了中国主流学术数据库（知网、万方、维普等），提供从文献导入、PDF/网页阅读标注、引用生成到 Word 插件的完整学术工作流。

---

## ✨ 功能亮点

- 📚 **22 种文献类型** — 期刊论文、学位论文、专利、标准……覆盖所有学术场景
- 🇨🇳 **六大中文学术源** — CNKI 知网 / 万方 / 维普 / 豆瓣读书 / 读秀 / 文津，一键抓取元数据
- 📖 **PDF + 网页双阅读器** — 原生 PDFKit 渲染 + 智能网页提取，统一标注体验
- 🎬 **YouTube 转录集成** — 自动获取视频字幕，嵌入笔记存档
- 📝 **Word 插件** — 本地 HTTP 服务驱动，插入引用/参考文献/实时刷新，无需云端
- ⌨️ **命令行工具** — 16+ 子命令，JSON 输出，适合脚本自动化
- 🔍 **FTS5 全文搜索** — 毫秒级检索，支持 `author:` `year:` `journal:` `type:` 高级语法
- 🎨 **7 种引用样式** — APA / MLA / Chicago / IEEE / Harvard / Vancouver / Nature，内置 citeproc-js 引擎

---

## 📋 功能详述

### 文献管理

- **22 种结构化文献类型**：期刊论文、图书、学位论文、会议论文、报告、专利、标准、网页、视频等，每种类型配有独立图标
- **层级收藏夹**：支持父子层级的文件夹体系，灵活组织文献
- **彩色标签**：自定义颜色标签，多对多关联，快速分类筛选
- **高级搜索**：基于 SQLite FTS5 的全文搜索引擎，索引标题、作者、期刊、摘要、笔记、DOI 等 8 个字段
  - 支持高级过滤语法：`author:Smith year:2020-2024 journal:Nature type:journalArticle`
- **智能排序**：按添加日期、年份、标题等多维排序

### 元数据获取

**国际学术源：**
- DOI → CrossRef API（支持 Polite Pool 优先通道）
- PMID → PubMed Central
- arXiv → arXiv API（多种标识格式）
- ISBN → 图书数据库
- 内存缓存（5 分钟 TTL / 50 条上限），避免重复请求

**中文学术源：**
- **CNKI 知网** — 基于 WKWebView 的智能元数据提取
- **万方数据** — 期刊/学位论文/会议论文
- **维普** — 中文科技期刊
- **豆瓣读书** — 图书元数据
- **读秀** — 图书馆联合目录
- **文津** — 国家图书馆数据

### 元数据验证

- **人工审核流程**：多候选源对比 UI，人工选择最佳元数据
- **四种验证状态**：`legacy` / `pending` / `verified` / `rejected`
- **证据哈希**：每次验证生成 Evidence Bundle Hash，确保审计可追溯
- **审核者归属**：记录验证人与时间戳
- **批量验证队列**：高效处理大量待审文献

### PDF 阅读器

- **原生 PDFKit 渲染**：流畅的 PDF 阅读体验
- **智能浮动工具栏**：选中文字后自动弹出标注工具，智能跟随选区位置
- **标注工具**：
  - 🟡 高亮（6 种颜色：黄、绿、青、粉、橙、紫）
  - ➖ 下划线
  - 📝 锚定笔记（可附加文字注释）
- **侧边栏**：
  - 📑 目录导航（PDF Outline）
  - 🏷️ 标注列表（点击跳转，就地编辑）
  - ℹ️ 文献信息（元数据详情）
- **页码计数 + 缩放控制**

### 网页阅读器

- **双显示模式**：
  - **剪藏正文**（默认）— 使用 Defuddle + Readability 提取的文章内容
  - **在线阅读** — 实时从原始 URL 提取可读内容
- **智能提取管线**：Defuddle → Readability → YouTube TV 降级，逐级尝试
- **标注系统**：与 PDF 阅读器统一的高亮/下划线/笔记标注
- **自适应排版**：可调字号（18-28pt）+ 响应式内容宽度
- **YouTube 集成**：
  - 内嵌视频播放器
  - 自动获取字幕转录（Android InnerTube API → Watch Page 解析 → yt-dlp 降级）
  - 时间戳导航链接

### 引用与参考文献

- **7 种内置引用样式**：APA、MLA、Chicago、IEEE、Harvard、Vancouver、Nature
- **双引用模式**：作者-日期制（APA、Harvard）与编号制（IEEE、Vancouver、Nature）
- **高性能引用生成**：纯字符串操作，< 0.1ms/条
- **citeproc-js 引擎**：嵌入 JavaScriptCore 运行 citeproc-js，完全符合 CSL 标准
- **线程安全池**：预热引擎池，消除冷启动延迟
- **智能缩写**：`Smith et al.` 自动缩写 + 编号范围压缩 `[2-4, 7]`
- **100+ CSL 样式**支持

### Word 插件

- **本地架构**：基于 macOS Network Framework 的 HTTP 服务器（`127.0.0.1:23858`），无需云端同步
- **核心功能**：
  - 📌 插入引用 — 浏览文献库，选择引用并插入
  - 📋 插入参考文献 — 在光标处生成完整文献列表
  - 🔄 刷新引用 — 文献变更后重新渲染所有引用
  - 🏷️ 引用标记 — 为上标引用附加文档元数据
- **自动安装**：应用启动时自动部署 Word 侧载清单（Manifest）
- **Task Pane UI**：在 Word 中直接搜索和浏览文献库

### 笔记编辑器

- **TipTap WYSIWYG 编辑器**：基于 ProseMirror 的富文本编辑
- **气泡菜单**：选中文字弹出格式工具栏（加粗、斜体、删除线、代码、列表、引用、链接）
- **Markdown ↔ HTML 双向转换**：Turndown + marked 引擎
- **预热 WebView 池**：< 500ms 编辑器启动
- **动态高度适配**：编辑器高度自动跟随内容

### 命令行工具（CLI）

| 命令 | 功能 |
|------|------|
| `search` | 全文搜索，JSON 输出 |
| `list` | 分页文献列表，可排序 |
| `get` | 按 ID 获取单条文献 |
| `add` | 新增文献（含字段校验） |
| `update` | 修改文献元数据 |
| `delete` | 删除文献（级联删除标注） |
| `move` | 移动文献到收藏夹 |
| `cite` | 生成引用（多样式） |
| `import` | 批量导入 BibTeX/RIS/JSON |
| `export` | 导出参考文献 |
| `collections` | 管理收藏夹 |
| `tags` | 管理标签 |
| `annotations` | 查询 PDF/网页标注 |
| `styles` | 列出引用样式 |
| `tag-docx` | 为 .docx 文件中的上标引用附加元数据 |

### 导入/导出

**导入格式：**
- BibTeX（高性能扫描器解析，处理转义字符、嵌套花括号、引用键自动去重）
- RIS（研究信息标准格式，多值字段支持）
- 批量导入（DOI/ISBN/PMID/arXiv + 中文标题自动识别）
- CNKI 链接导入（直接解析 URL）
- 网页剪藏（Obsidian Clipper 管线）

**导出格式：**
- BibTeX（智能引号处理 + 标准字段排序）
- RIS
- JSON（CSL-JSON）
- DOCX 引用标记

---

## 🛠️ 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | SwiftUI（macOS 14.0+） |
| 数据库 | GRDB 6.24（SQLite ORM + 响应式查询） |
| PDF 渲染 | PDFKit（原生） |
| 网页渲染 | WebKit（WKWebView + JavaScript 注入） |
| 引用引擎 | citeproc-js（JavaScriptCore 嵌入） |
| 笔记编辑 | TipTap / ProseMirror（WKWebView） |
| CLI 框架 | Swift Argument Parser 1.3 |
| 翻译后端 | Node.js（嵌入式进程，Zotero 翻译器协议） |
| Word 插件 | Network Framework HTTP 服务器 + Office JS API |

---

## 💻 系统要求

- **操作系统**：macOS 14.0 (Sonoma) 或更高版本
- **架构**：Apple Silicon (arm64) / Intel (x86_64)
- **磁盘空间**：约 200MB（含嵌入式 Node.js 运行时）

---

## 🔨 构建

### 前置条件

- Xcode 15.0+
- Node.js 20+（用于翻译后端，构建脚本会自动下载嵌入式 Node.js）

### 构建步骤

```bash
# 克隆仓库
git clone git@github.com:NickHood1984/SwiftLib.git
cd SwiftLib

# 安装翻译后端依赖
cd swiftlib-translation-backend
npm install
cd ..

# 获取翻译后端 vendor 依赖（translation-server + translators_CN）
# 请参考 swiftlib-translation-backend/README.md

# 构建应用 + CLI + DMG
./scripts/build-app.sh

# 或直接使用 Swift Package Manager 运行
swift run SwiftLib
```

构建产物位于 `build/` 目录：
- `SwiftLib.app` — 主应用
- `swiftlib-cli` — 命令行工具
- `SwiftLib-Debug.dmg` — 分发镜像

---

## 📁 项目结构

```
SwiftLib/
├── Sources/
│   ├── SwiftLib/              # macOS 主应用
│   │   ├── Views/             # SwiftUI 视图层
│   │   ├── Services/          # 应用服务（元数据提取、翻译后端管理等）
│   │   ├── Helpers/           # 工具类
│   │   ├── ReaderExtraction/  # 网页内容提取（Defuddle / Readability）
│   │   ├── Server/            # Word 插件 HTTP 服务器
│   │   └── Resources/         # 静态资源（JS、CSS、CSL 样式）
│   ├── SwiftLibCore/          # 共享核心库
│   │   ├── Models/            # 数据模型（Reference、Collection、Tag 等）
│   │   ├── Database/          # GRDB 数据库层 + 迁移
│   │   ├── Citation/          # 引用格式化 + citeproc-js 引擎
│   │   ├── Services/          # 核心服务（元数据获取、BibTeX 解析等）
│   │   └── Resources/         # CSL 样式文件 + citeproc-js 引擎
│   ├── SwiftLibCLI/           # 命令行工具
│   └── SwiftLibProbe/         # 调试探针
├── Tests/                     # 单元测试
├── scripts/
│   ├── build-app.sh           # 构建脚本
│   └── note-editor/           # TipTap 笔记编辑器（JS）
├── swiftlib-translation-backend/  # Node.js 翻译后端
├── WordAddin/                 # Word 插件前端
├── Docs/                      # 开发文档
└── Package.swift              # Swift Package Manager 配置
```

---

## � 开源致谢

本项目依赖以下开源组件，特此致谢并遵守其各自许可证：

| 组件 | 版本 | 许可证 | 用途 |
|------|------|--------|------|
| [Zotero Translation Server](https://github.com/zotero/translation-server) | 2.0.5 | AGPL-3.0 | 网页元数据抓取后端，随应用捆绑运行 |
| [translators_CN](https://github.com/l0o0/translators_CN) | — | AGPL-3.0 | 中文学术网站 Zotero 转换器（知网、万方、维普等） |
| [citeproc-js](https://github.com/Juris-M/citeproc-js) | 1.4.61 | AGPL-3.0 | CSL 引用格式化引擎，嵌入 JavaScriptCore 运行 |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | — | MIT | SQLite 数据库 ORM |
| [Readability.js](https://github.com/mozilla/readability) | — | Apache-2.0 | 网页正文提取 |
| [Defuddle](https://github.com/kepano/defuddle) | — | MIT | 网页内容清洗与结构化提取 |

> **AGPL-3.0 说明**：Zotero Translation Server、translators_CN 及 citeproc-js 均采用 AGPL-3.0 许可证。根据该许可证要求，本项目在分发时须注明上述组件的使用，并保留其原始许可证文本。各组件源代码可通过上方链接获取。

---

## �📄 许可证

本项目为私有项目，暂未公开发布。
