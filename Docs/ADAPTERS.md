# Site Adapters — 维护手册

> **If you are an AI repair agent**, your primary input is [`ADAPTERS_REPAIR.md`](ADAPTERS_REPAIR.md) (deterministic runbook) and [`adapter-schema.json`](adapter-schema.json) (machine-readable constraints). Read those first and only this file for background. Invented values (transforms / kinds / postProcess) silently produce wrong results — the schema file enumerates what's actually implemented.

SwiftLib 的元数据抓取层用 **JSON 适配器** 描述 "怎么抓数据"，Swift 代码只负责执行。
当上游（豆瓣 / CrossRef / OpenAlex / CNKI ...）改版时，绝大多数修复只需要编辑一份 JSON，
**不用重编译、不用发版**。

## 文档导航

| 文件 | 受众 | 用途 |
|---|---|---|
| `ADAPTERS.md`（本文） | 人类开发者 | 概览 + 维护流程 + 变更故事 |
| [`ADAPTERS_REPAIR.md`](ADAPTERS_REPAIR.md) | AI agent （主）/ 人类（次） | 确定性投放的修复步骤、反向约束、提示词模板 |
| [`adapter-schema.json`](adapter-schema.json) | AI agent / 编辑器 | JSON Schema，枚举合法 transform / postProcess / kind / field 结构 |
| `Sources/SwiftLibCore/Resources/adapters/*.json` | 热修复目标 | 有 6 个适配器配置 + canary fixtures |
| `scripts/canary.sh` | CI + 本地 | 一键实践验证 (需 `SWIFTLIB_CANARY=1`) |

---

## 1. 适配器是什么

**位置**：`Sources/SwiftLibCore/Resources/adapters/<id>.json`

**运行时**：`SiteAdapterRuntime`（`Sources/SwiftLibCore/Adapters/SiteAdapterRuntime.swift`）
- `extractJSON(route:data:)` → 按 JSON 路径和过滤器提取结构化数据
- `extractHTML(route:html:)` → 按正则（带 `stripTags` 选项）提取 HTML 字段
- `expandURL(_:context:)` → 模板 `{placeholder}` 替换

**加载**：`SiteAdapterRegistry.shared.adapter(id:)`，从 bundle 读取 + 支持测试覆盖路径。

### 1.1 一个适配器的最小骨架

```jsonc
{
  "id": "douban-book",
  "schemaVersion": 1,
  "displayName": "豆瓣读书",
  "description": "…",

  "routes": {
    "search": {
      "url": "https://book.douban.com/j/subject_suggest?q={query}",
      "headers": { "Referer": "https://book.douban.com" },
      "timeoutSeconds": 10,
      "extract": {
        "kind": "json",
        "itemsPath": "$",
        "itemFilter": { "field": "type", "equals": ["b", "book"] },
        "fields": {
          "title":     { "paths": ["title"] },
          "authorRaw": { "paths": ["author_name", "extra_attrs.author"] },
          "year":      { "paths": ["year"], "transform": "prefix4Int" }
        }
      }
    },

    "detail": {
      "url": "{subjectUrl}",
      "extract": {
        "kind": "html",
        "fields": {
          "isbn": {
            "strategies": [
              { "kind": "regex",
                "pattern": "<meta[^>]+property=\"book:isbn\"[^>]+content=\"([0-9Xx]{10,13})\"",
                "group": 1 }
            ],
            "transform": "upper"
          }
        }
      }
    }
  },

  "canary": [
    { "name": "高级水生生物学 1999",
      "searchQuery": "高级水生生物学",
      "subjectUrl": "https://book.douban.com/subject/1554675/",
      "expectSearch": { "subjectId": "1554675" },
      "expectDetail": { "isbn": "9787030069870", "publisher": "科学出版社" } }
  ]
}
```

### 1.2 字段参考

**JSON extract**
| 字段 | 作用 |
|---|---|
| `itemsPath` | 指向要迭代的数组；`"$"` = 根本身就是数组；`"results"` = 取根对象的 `results` 子数组 |
| `itemFilter.field` + `.equals` | 按字段值过滤；不在白名单里的跳过 |
| `fields[name].paths` | 候选路径列表，按顺序找第一个非空 |
| `fields[name].template` | **（计算字段）** 用 `{path}` 占位符渲染，如 `"{biblio.first_page}-{biblio.last_page}"` |
| `fields[name].elideIfMissing` | 配合 `template`：只要列出的 path 任一缺失就返回 `null`，避免产出 `"101-"` 这种半成品 |
| `fields[name].separator` | 当路径解析结果是数组时的 join 分隔符（默认 `"|"`） |
| `fields[name].transform` | **字符串级** 后处理：`prefix4Int` / `upper` / `lower` / `trim` / `stripDoiOrgPrefix` |
| `fields[name].postProcess` | **原始值级** 后处理（作用于 stringify 之前）：当前支持 `reconstructInvertedIndex`（OpenAlex 倒排索引 → 平文本） |

路径语法子集：

| 语法 | 含义 |
|---|---|
| `$` | 根本身 |
| `$.foo` / `foo` | 取子键 |
| `foo.bar` | 嵌套键 |
| `foo[0]` | 数组下标 |
| `foo[*]` | **数组通配符** —— 后续路径 map 到每个元素 |
| `authorships[*].author.display_name` | 嵌套 + 通配符混用，返回字符串数组（交给 `separator` join） |
| `ISBN:{isbn}` | **itemsPath 本身可模板**：调用 `extractJSON(context:)` 时传入 `{"isbn": "xxx"}`，运行时展开 — 专为 Open Library 这种根键动态的设计而生 |

**HTML extract**
| 字段 | 作用 |
|---|---|
| `fields[name].strategies[].kind` | 目前只支持 `regex` |
| `fields[name].strategies[].pattern` | NSRegularExpression，默认 case-insensitive + `dotMatchesLineSeparators` |
| `fields[name].strategies[].group` | 捕获组号（1 开始） |
| `fields[name].strategies[].stripTags` | `true` 时剥 `<…>` + 压缩空白 |

**URL 模板**
- `{key}` 会替换成 `expandURL(_:context:)` 的 `context[key]`
- 若 key 名字以 `Url` / `URL` 结尾（如 `{subjectUrl}`），值**原样替换**（不做 percent-encoding），适合占位整条 URL 的情况
- 否则做 URL query percent-encoding
- 替换后若出现空的 `&key=` 查询参数（比如未配置 `contactEmail` 时的 `&mailto=`），runtime 自动清理

---

## 2. 日常维护工作流

### 2.1 本地跑 canary（真实网络请求）

```bash
SWIFTLIB_CANARY=1 swift test --filter CanaryIntegrationTests
```

- 默认 CI 不跑（会跳过这个 suite）
- 命中 `Resources/adapters/*.json` 里每个 `canary[]`
- 失败通常意味着上游 schema 飘了

### 2.2 CI 里定时跑

推荐 GitHub Actions nightly：

```yaml path=null start=null
# .github/workflows/canary.yml
name: Adapter Canary
on:
  schedule: [{ cron: "0 12 * * *" }]
  workflow_dispatch:
jobs:
  canary:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: SWIFTLIB_CANARY=1 swift test --filter CanaryIntegrationTests
      - if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              ...context.repo,
              title: "Adapter canary failed",
              body: `Run: ${context.payload.repository.html_url}/actions/runs/${context.runId}`,
              labels: ["adapter-drift"]
            })
```

---

## 3. 上游 schema 漂移了怎么修

### 3.1 诊断（手动版）

```bash
# 拉 canary URL 看实际返回
curl -sS -H "User-Agent: Mozilla/5.0" \
     "https://book.douban.com/j/subject_suggest?q=高级水生生物学" \
  | python3 -m json.tool

# 和 adapter JSON 里期望的字段名做对比
```

常见漂移模式：
- 字段重命名（`extra_attrs.author` → `author_name`）
- 枚举值变化（`"type": "book"` → `"type": "b"`）
- 嵌套层级变动（扁平化 / 下沉）
- HTML 结构改版（class 名字变了，info block 重写）

### 3.2 修复流程

1. **编辑 `Resources/adapters/<id>.json`**
   - 给 `fields[name].paths` 追加新路径（**保留旧路径作为回退**）
   - 更新 `itemFilter.equals` 接受新旧枚举
   - HTML 适配器给 `strategies` 追加新的 regex，**老 regex 留着**
2. **bump `schemaVersion`**（便于排障/追溯）
3. **更新 canary expected**（如果字段本身语义变了）
4. **本地跑 canary 确认**：`SWIFTLIB_CANARY=1 swift test --filter CanaryIntegrationTests`
5. **PR + 合入**

### 3.3 AI 辅助自愈（推荐的工作流）

当 nightly canary 挂掉，触发一个 Warp Cloud Agent 或等价 LLM 任务：

**prompt 骨架**：
```
我有一个失败的适配器 canary：
- Adapter: ${adapterId}
- Canary: ${canaryName}
- Expected: ${expected}
- Got: ${actualExtractedRow}
- Live response (first 8 KB): ${snippet}

请：
1. 指出 schema 漂移（哪个字段改了名 / 改了枚举值 / 改了位置）
2. 给出一个最小 JSON patch，在 `fields[*].paths` 或 `strategies` 里追加新规则
3. 保持所有旧规则作为 fallback
4. 若 canary 的 expected 本身需要调整，说明原因
```

建议让 agent 具备：
- Playwright / `curl` 能力（拉 live 响应）
- 读取 `Resources/adapters/**` + `Docs/ADAPTERS.md`
- 改一份 branch + 跑 canary + 开 PR
- **无权合入**，只能建议（由人审核）

---

## 4. 加一个新源的步骤

仓库已自带 **6 个完整可运行示例**（全部通过联网 canary）：

| 适配器 | 演示能力 |
|---|---|
| `douban-book.json` | HTML + JSON 混合、search → detail 级联 |
| `openalex-work.json` | 数组通配符 `[*]`、`template` + `elideIfMissing`、`reconstructInvertedIndex` postProcess、polite-pool `{mailto}` |
| `crossref-work.json` | 嵌套数组下标 `date-parts[0][0]`、`titleWithSubtitle` 模板、`stripHtmlTags` (JATS)、平行作者数组 + Swift mapper 拼接 |
| `semantic-scholar-paper.json` | 3 条路由（byDoi / byTitleMatch / abstractByDoi），共享字段集 |
| `google-books-volume.json` | 平行 `industryIdentifiers[*].type` + `[*].identifier` 让 mapper 按 ISBN_13/10 选优 |
| `openlibrary-book.json` | **itemsPath 本身是模板** — `"ISBN:{isbn}"` — 处理根键动态的响应 |

加一个新源（以 **CrossRef 单篇查询** 为例）：

1. 复制最接近目标的现有 JSON 做模板（CrossRef 是 JSON → 拿 `openalex-work.json`）
2. 改 `id` / `displayName` / `description`
3. 定义 routes：
   - 纯 JSON 路由 → `"kind": "json"`，指定 `itemsPath`
   - 单对象返回（如 `/works/{doi}` 返回的 root 是 object）→ `itemsPath: "$"` + `rows.first`
   - HTML detail 路由 → `"kind": "html"`，每字段写 ≥1 条锚定正则
4. 为每个字段写 **2+ 条候选 `paths`**（上游可能重命名字段：CrossRef 历史上 `container-title` 一直稳定，但像 `publisher-location` 这类偶尔漂移）
5. **用 `template` 重组** — 例如 `"pages": { "template": "{page.start}-{page.end}" }`
6. **数组字段** — author 之类的：`"authors": { "paths": ["author[*].given"], "separator": "|" }`
7. 挑 1–3 个 stable DOI / URL（发表超 3 年，关键字段完整）做 canary
8. 本地 `curl` 拉一次，把响应里能确认的字段填进 `expectSearch` / `expectDetail`
9. 在 `MetadataFetcher` 里加一个小 mapper 把 `[String: String]` 行转成 `Reference`（参考 `referenceAndEnrichmentFromOpenAlexRow`）
10. `swift test --filter SwiftLibCoreTests` 看单测绿，再 `./scripts/canary.sh` 联网跑一把

**不需要动的东西**：runtime、registry、性能 / 限流 / 熔断层、调用点（`ParallelSourceFetcher` 等消费者）。

---

## 5. WebView 订阅源打通（已落地）

**适用场景**：Scopus / Web of Science / Elsevier ScienceDirect 等需要机构订阅、没有公开 API key 的源。用户已在浏览器中 SSO 登录过，cookie 保存在 `WebSessionBroker` 的 `WKWebsiteDataStore` 中，隐藏 `WKWebView` 加载时自动复用这些会话。

**示例 adapter**（`kind: webView`）：

```jsonc path=null start=null
{
  "id": "scopus-article",
  "schemaVersion": 1,
  "requiresAuthenticatedSession": true,
  "routes": {
    "byDoi": {
      "url": "https://www.scopus.com/record/display.uri?eid=2-s2.0-...&doi={doi}",
      "kind": "webView",
      "extract": {
        "kind": "html",
        "fields": { ... }
      }
    }
  }
}
```

**执行链路**：
1. `SiteAdapterDefinition.Route.kind` 支持 `.http`（默认）和 `.webView` —— 已在 schema + Swift 枚举中实现。
2. `MetadataFetcher.fetchAdapterRequest(route:url:parser:)` 自动分发：
   - `kind == .http` → 走原有 `performRequest`（URLSession + 限流/熔断/重试）。
   - `kind == .webView` → 调用注册的 `MetadataFetcher.webViewExecutor`。
3. `WebViewAdapterExecutorImpl`（在 `SwiftLib` app target 中）：
   - 复用 `WebSessionBroker` 按 host 隔离的 `WKWebsiteDataStore`（cookie 永久性留存）。
   - 创建隐藏 `WKWebView`，加载 URL，等待 `didFinish` + 1s JS 渲染延迟。
   - 根据 `extract.kind` 获取页面内容：
     - `.html` → `document.documentElement.outerHTML`
     - `.json` → `document.body.innerText`（适用于 JSON endpoint）
   - 返回 UTF-8 `Data`，由 `SiteAdapterRuntime.extractHTML/extractJSON` 继续解析。
4. 限速：WebView 源同样受 `HostRateLimiter` + `HostCircuitBreaker` 约束；adapter JSON 中不设独立限速。
5. `requiresAuthenticatedSession: true` 给 UI 层一个信号，首次调用时可弹出登录引导而不是默默失败。

**Canary 策略**：
- 本地 canary：`WebViewAdapterExecutorImpl` 复用本机 cookie store，直接跑 `expectSearch` / `expectDetail` 断言。
- CI canary：可将测试机构的 session cookie 加密后放入 GitHub Actions secrets，仅用于验证一篇旧论文页面，避免触发反爬。

**合规 / 伦理边界**：个人订阅学术数据库用于个人科研，本质上和浏览器中手动复制粘贴相同，一般属合理使用范围。具体 ToS 因机构而异——适配器 `description` 应明确说明 "User is responsible for verifying their institutional subscription ToS allows tool-assisted retrieval"。

---

## 6. 安全与性能

- **不要用 adapter 执行任意代码**。运行时只懂正则和 JSON 路径；没有 eval。
- **正则必须锚定**。用 `<span class="pl">\s*ISBN:?\s*</span>` 这样的锚点，避免在长 HTML 里误匹配。
- **每个源的配额**由 `HostRateLimiter` 统一管理，adapter JSON 里不设限速。
- **熔断**由 `HostCircuitBreaker` 负责；adapter 层不需要处理。
- **超时**通过 `timeoutSeconds` 每 route 可覆盖；search ~10s，detail ~15s 够用。

---

## 6. TL;DR 维护 checklist

- 新增/修改适配器：编辑 `Resources/adapters/<id>.json`，`schemaVersion++`，跑 `SWIFTLIB_CANARY=1 swift test --filter CanaryIntegrationTests` 确认
- 上游改版：把旧规则留在 fallback，新规则追加到前面
- canary 失败：先 curl 比对，再 patch JSON，不要动 Swift
- 加新源：JSON + canary + 在调用点走 `SiteAdapterRegistry`
