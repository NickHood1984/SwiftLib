# SwiftLib 1.4.1

## 新增

- **统一 CSL 渲染**：App 内预览、详情和插件刷新统一走 citeproc-js，降低不同入口的引文格式差异。
- **库体检**：新增 CSL 字段完整性、验证状态和元数据来源统计，帮助定位缺卷期页码、出版项或作者信息的条目。
- **Word 脚注引文**：Word 插件支持 note/footnote 样式的真实脚注引文，并保存 locator、prefix、suffix 等 cite-item 选项。

## 改进

- **CNKI 元数据刷新**：支持远程 selector 热更新，并以详情页解析为主，补齐搜索结果页可能看不到的卷、期、页码等字段。
- **维普检索解析**：从出版信息行读取年份、期号和页码，避免标题里的年份范围干扰出版年判断。
- **标识符归一化**：增强 DOI、ISBN、ISSN、PMID、PMCID、arXiv 的规范化，用于去重、CSL 输出和 DOI 内容协商。
- **导入反馈**：批量导入会区分新增、合并和更新结果，减少重复导入时的状态不明确。
- **DOCX 刷新**：可读取脚注中的 SwiftLib 引文，并从 Custom XML 回填 cite-item 选项，提升跨文档编辑稳定性。

## 修复

- 修复 `swift run SwiftLib` 开发运行时 Sparkle 启动干扰调试的问题。
- 修复 SwiftPM citation fixture 资源警告。
- 修复 CSL golden snapshot 测试运行时间异常的问题。
