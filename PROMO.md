# SwiftLib 宣发文案

---

## 📕 小红书文案

### 文案一：痛点切入版

---

**标题：** 受够了 Zotero 对中文文献的水土不服？这款 Mac 原生文献管理工具太香了 🍎

---

姐妹们/兄弟们，写论文的痛谁懂啊 😭

用 Zotero 吧，知网万方的文献抓不全，中文元数据一塌糊涂
用 EndNote 吧，贵就算了，界面丑到怀疑人生
用 Mendeley 吧，早被 Elsevier 摆烂了……

所以！！我自己做了一个 👇

**SwiftLib** — 专为中国学术研究者打造的 macOS 文献管理工具

✅ **知网/万方/维普/豆瓣/读秀/文津** 六大中文数据库直连抓取
✅ **DOI / PMID / arXiv / ISBN** 国际源一键导入
✅ **PDF 阅读器** 6 色高亮 + 下划线 + 锚定笔记，浮动工具栏跟着选区走
✅ **网页剪藏** 自动提取网页正文，YouTube 视频连字幕都给你抓下来
✅ **Word 插件** 不用云端！本地服务一键插入引用和参考文献
✅ **7 种引用样式** APA / MLA / Chicago / IEEE 随便切
✅ **全文搜索** `author:张三 year:2020-2024` 秒级定位
✅ **命令行工具** 程序员最爱，16 个子命令全 JSON 输出

而且——它是 **macOS 原生 SwiftUI** 开发的！
不是 Electron 套壳，不是网页版，丝滑程度你试过就回不去了 🥹

💡 适合人群：
- 硕博在读，天天和文献打交道的
- 经常引用中文文献，受够了 Zotero 抓取质量的
- Mac 用户，对应用品质有要求的
- 想把文献管理 + 阅读标注 + Word 引用一站搞定的

🔮 目前还在内测打磨中，敬请期待正式发布～

\#文献管理 #学术工具 #Mac应用 #论文写作 #研究生必备 #知网 #Zotero替代 #macOS #学术神器 #SwiftUI

---

### 文案二：功能展示版

---

**标题：** 自研 Mac 文献管理工具，知网万方一键导入 + PDF 智能标注 + Word 引用插件 📚

---

做学术的 Mac 用户看过来！

花了很长时间开发了一款 **macOS 原生文献管理工具**，分享一下核心功能 👇

**【文献管理】**
📂 22 种文献类型全覆盖（期刊、学位论文、专利、标准…）
🏷️ 层级收藏夹 + 彩色标签，怎么分类都行
🔍 全文搜索引擎，支持 `author:` `year:` `journal:` 语法

**【中文学术源直连】**
🇨🇳 知网 CNKI / 万方 / 维普 / 豆瓣读书 / 读秀 / 文津
一键抓取元数据，告别手动录入

**【阅读 & 标注】**
📖 PDF 原生阅读器：黄绿青粉橙紫 6 色高亮，浮动工具栏
🌐 网页阅读器：自动提取正文 + YouTube 字幕转录
📝 TipTap 富文本笔记编辑器

**【引用 & Word】**
✏️ APA / MLA / Chicago / IEEE / Harvard / Vancouver / Nature
📎 Word 插件：本地运行，插入引用→参考文献→一键刷新
📤 导出 BibTeX / RIS / JSON

**【极客友好】**
⌨️ 命令行工具 16+ 子命令
🧩 citeproc-js 引擎嵌入 JavaScriptCore
⚡ 引用渲染 < 0.1ms

纯 SwiftUI 原生开发，不套壳不糊弄 ✨

\#学术工具 #文献管理 #Mac开发 #SwiftUI #独立开发 #论文工具 #研究生日常

---

## 🐦 技术社区文案（V2EX / 即刻 / Twitter / X）

### 版本一：技术向

---

**SwiftLib — macOS 原生学术文献管理工具**

用 SwiftUI + GRDB + JavaScriptCore 构建了一个完整的学术文献管理系统。几个技术上比较有意思的点：

1. **嵌入式 citeproc-js 引擎** — 在 JavaScriptCore 里运行 citeproc-js，线程安全池 + 预热机制，单次引用渲染 < 0.1ms
2. **六大中文学术数据库集成** — CNKI/万方/维普/豆瓣/读秀/文津，基于 WKWebView 的元数据智能提取
3. **YouTube 转录获取** — Android InnerTube API 模拟 → Watch Page HTML 解析 → yt-dlp 降级，四级 fallback
4. **Word 插件本地化** — 用 Network Framework 搭了个 HTTP 服务器（127.0.0.1:23858），直接驱动 Word Add-in，不走云端
5. **翻译后端** — 内嵌 Node.js 进程运行 Zotero translation-server，overlay 覆盖系统支持中文学术翻译器热更新
6. **FTS5 全文搜索** — SQLite FTS5 + Unicode61 分词，支持 `author:` `year:2020-2024` `type:journalArticle` 结构化语法
7. **GRDB 响应式架构** — ValueObservation 驱动 UI 实时更新，从数据库到视图的声明式绑定

Tech Stack: SwiftUI / GRDB 6.24 / PDFKit / WebKit / JavaScriptCore / Node.js / TipTap / Swift Argument Parser

目前 private repo，还在打磨中。

---

### 版本二：产品向

---

**做了一个给中国学术研究者用的 Mac 文献管理工具**

主要解决的痛点：

- Zotero 对中文学术数据库支持差（知网/万方/维普的元数据经常抓不全或格式错乱）
- 现有工具的 PDF 标注体验割裂（要么功能弱，要么要额外跳转到其他 app）
- Word 引用插件依赖云端或配置繁琐

SwiftLib 的做法：

→ 直连 6 个中文学术数据库 + 国际四大标识符（DOI/PMID/arXiv/ISBN）
→ 原生 PDF 阅读器 + 网页阅读器，统一标注系统（高亮/下划线/笔记）
→ 本地 HTTP 服务器驱动 Word 插件，零配置开箱即用
→ 嵌入 citeproc-js 引擎，7 种内置样式 + 100+ CSL 样式
→ 内建命令行工具，16 子命令 JSON 输出，适合自动化工作流
→ macOS 原生 SwiftUI，不是 Electron 套壳

还在内测阶段，欢迎反馈和交流 🙏

---

### 版本三：推特/X 短文案

---

Built a native macOS reference manager for Chinese academic researchers 🇨🇳📚

- Direct integration with CNKI, Wanfang, VIP + DOI/PMID/arXiv/ISBN
- PDF & web reader with unified annotation system
- Word add-in powered by local HTTP server (no cloud)
- Embedded citeproc-js engine in JavaScriptCore
- CLI with 16+ subcommands
- SwiftUI + GRDB + PDFKit + WebKit

Still in private beta. Built with Swift, for Mac. 🍎

---

## 📋 GitHub 仓库描述（About）

**简短版（用于 GitHub repo description）：**

> macOS 原生学术文献管理工具 — 深度集成中文学术数据库（CNKI/万方/维普），PDF/网页阅读标注，Word 引用插件，citeproc-js 引擎，命令行工具。SwiftUI + GRDB。

**英文版：**

> Native macOS academic reference manager with deep Chinese academic database integration (CNKI/Wanfang/VIP), PDF & web reader with annotations, Word citation add-in, embedded citeproc-js engine, and CLI tools. Built with SwiftUI + GRDB.
