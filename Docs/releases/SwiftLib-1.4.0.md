# SwiftLib 1.4.0

## 新增

- **工作区（Workspace）**：支持 all、manual、smart、hybrid 四种类型，持久化 sidebar 选区、搜索文本、列可见性及布局快照，可同时维护多个研究上下文。
- **万方数据 + 维普（VIP）检索**：新增两个中文期刊平台浏览器检索通道，作为 CNKI 的平行来源，支持候选结果排序与相似度过滤。
- **CLI DOCX 命令**：`refresh-docx`（刷新引文编号与参考文献表）、`docx-audit`（检查引文一致性）、`prune-unused`（裁剪文献库未使用条目）。
- **Word 插件 zh-CN 语言包**：补齐中英混排引文的术语、日期格式与标点输出。
- **隐藏 WKWebView 媒体守护**：防止后台 WebView 意外触发摄像头/麦克风权限弹窗或自动播放音频。

## 维护

- 重构元数据管线目录（`SwiftLibCore/Metadata/`）、App target 目录结构与数据库 domain extension 分层。
- AI 助手 DOM 选择器升级至 v11（2026-05-14），重新验证 ChatGPT、DeepSeek、豆包、Kimi。
