# 元数据管线修复验证清单（2026-06-10）

本轮修复涉及限速/熔断、CSL 样式加载、并行源抓取、中文链路（万方/维普评分、百度回退、共识合并）。
算法层已在沙盒中用 Python 复算通过（评分阈值、年份梯度、限速器排队行为）；以下为 Mac 上的
端到端验证步骤。

## 1. 单元测试（约 2 分钟）

```bash
swift test --filter HostRateLimiterTests
swift test --filter HostCircuitBreakerTests
swift test --filter CSLManagerImportTests
swift test --filter ParallelSourceFetcherTests
swift test --filter ChineseStructuredCandidateTests
swift test --filter ChineseMetadataConsensusTests
# 回归面：合并/验证/引用渲染不应有任何失败
swift test --filter MetadataResolutionTests
swift test --filter CitationGoldenSnapshotTests
```

预期：全部通过。`CitationGoldenSnapshotTests` 同时验证 restoreProcessorState 快速重置
与完整重建引擎输出逐字节一致。

## 2. 速度验证（手工，约 10 分钟）

| 场景 | 操作 | 修复前典型 | 预期修复后 |
|---|---|---|---|
| 引用预览渲染 | 库列表滚动 50 条（冷缓存），观察右侧引文预览出现速度 | 每条数百 ms，肉眼可见逐条加载 | 第一条后接近即时 |
| 英文 DOI 批量刷新 | 选 10 条带 DOI 英文文献 → 批量刷新，计总时长 | S2 429 时单条可拖 30–40s | 单条最长约 15s（软超时）|
| 批量刷新限速 | 刷新时用 Console.app 过滤 `swiftlib` 看 429 日志 | 成批 429 | 偶发或无 |

## 3. 中文链路准确性验证（手工，约 15 分钟）

1. **万方/维普评分**：找一条知网检索质量差的中文文献刷新，进入候选确认窗口，
   检查候选百分比是否有区分度（不再整排 45%），弱相关条目沉底。
2. **中文作者**：从万方/维普候选导入一条，检查作者是否为完整中文名
   （详情页不出现"姓=三 名=张"式拆分），GB/T 7714 预览作者正确。
3. **百度回退**：刷新一条知网/万方/维普都搜不到的中文文献（如早年会议论文），
   预期出现"已从百度学术检索到候选"的确认队列条目，而非直接"未找到"。
4. **批量并发**：同时刷新 3 条中文文献，确认第 2、3 条不再立刻报
   "未找到候选"（回退通道排队生效）。

## 4. CSL 样式验证（约 5 分钟）

1. 从 [Zotero Style Repository](https://www.zotero.org/styles) 下载任意 .csl
   （其 `<id>` 为 URL 形式）→ 设置中导入。预期：导入成功（修复前必然失败）。
2. 修改该 .csl 的某个标点后重新导入，预期：引文预览立即按新样式输出（无需重启）。
3. 删除该样式，预期：样式列表与预览同步更新。

## 沙盒内已完成的算法验证记录

- 评分复算：精确匹配 1.000；弱相关 0.020（旧实现虚标 0.45）；作者+年份+期刊
  提升 +0.400；年份梯度 0.720 > 0.660 > 0.620。
- 限速器仿真（200ms 间隔，6 并发）：旧实现 5 个请求同时发出（限速失效）；
  新实现严格 ~200ms 排队。
