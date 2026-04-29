# SwiftLib 1.3.0

发布日期：2026-04-29

## 重点更新

- 新增 OCR Markdown 连续翻译：扫描版 PDF OCR 后，可通过现有 AI 助手窗口自动分批翻译整篇文档，并生成原文 + 小字译文的双语 Markdown。
- 新增可定制翻译 Prompt 和更宽容的译文解析器，能处理代码块 JSON、尾逗号、智能引号、标签式译文、纯文本译文和部分截断结果。
- 新增多源元数据管线：CrossRef、OpenAlex、Semantic Scholar、Open Library、Google Books、豆瓣读书、CNKI 与百度学术可按场景路由、并发抓取和字段级合并。
- 新增 JSON site adapter runtime，内置多个学术站点/API 适配器，并提供 adapter schema 与修复指南。

## 改进

- AI 助手现在会等待回复稳定后再抓取结果，减少“模型停顿一下就被当成结束”的误判。
- 待确认元数据窗口改为更平面的视觉样式，移除割裂的顶部条幅。
- OCR Markdown 渲染增强了 HTML 表格、上下标和论文片段的处理。
- Word 插件和本地服务的文档扫描、引用渲染、任务窗格交互更稳。
- 批量导入加入持久缓存、请求合并、限速和熔断，降低重复请求和上游失败影响。

## 修复

- 修复 DOI 末尾大写校验字符被强制小写的问题。
- 修复 AI 网页 selector 改版后可能无法注入、无法发送或无法抓回回复的问题。
- 修复 AI 返回 JSON 尚未完整时被提前解析导致“没有合法 JSON”的问题。

## 验证

- `swift build`
- `swift test --filter ImporterAndMetadataTests`
- 新增 OCR 翻译、AI 回复稳定性、site adapter、元数据验证和真实参考文献规则相关测试。
