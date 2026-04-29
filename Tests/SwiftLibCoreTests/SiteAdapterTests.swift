import XCTest
@testable import SwiftLibCore

final class SiteAdapterTests: XCTestCase {

    // MARK: - Runtime primitives

    func testExpandURLEncodesAndSubstitutes() {
        let expanded = SiteAdapterRuntime.expandURL(
            "https://example.com/?q={query}&p={page}",
            context: ["query": "高级水生生物学", "page": "1"]
        )
        XCTAssertTrue(expanded.contains("q=%E9%AB%98%E7%BA%A7"))
        XCTAssertTrue(expanded.contains("&p=1"))
    }

    func testExpandURLPreservesUnknownPlaceholders() {
        let expanded = SiteAdapterRuntime.expandURL(
            "https://example.com/{subjectUrl}",
            context: ["otherKey": "x"]
        )
        XCTAssertTrue(expanded.contains("{subjectUrl}"))
    }

    func testResolvePathSupportsDottedPathsAndArrayIndex() {
        let root: [String: Any] = [
            "a": [
                "b": ["first", "second", "third"],
                "c": ["d": 42]
            ]
        ]
        XCTAssertEqual(SiteAdapterRuntime.resolvePath(root: root, path: "$") as? [String: Any] != nil, true)
        XCTAssertEqual(SiteAdapterRuntime.resolvePath(root: root, path: "a.b[1]") as? String, "second")
        XCTAssertEqual(SiteAdapterRuntime.resolvePath(root: root, path: "$.a.c.d") as? Int, 42)
        XCTAssertNil(SiteAdapterRuntime.resolvePath(root: root, path: "a.b[99]"))
    }

    func testResolvePathWildcardMapsOverArrays() {
        // Mirrors OpenAlex's authorships[*].author.display_name shape.
        let root: [String: Any] = [
            "authorships": [
                ["author": ["display_name": "Alice"]],
                ["author": ["display_name": "Bob"]],
                ["author": ["display_name": "Carol"]]
            ]
        ]
        let result = SiteAdapterRuntime.resolvePath(
            root: root,
            path: "authorships[*].author.display_name"
        ) as? [Any]
        XCTAssertEqual(result?.compactMap { $0 as? String }, ["Alice", "Bob", "Carol"])
    }

    // MARK: - URL expansion quirks

    func testExpandURLDropsEmptyMailtoParam() {
        // Real scenario: OpenAlex route with `&mailto={mailto}` and no contactEmail
        // should not leave a dangling `&mailto=` in the URL.
        let expanded = SiteAdapterRuntime.expandURL(
            "https://api.openalex.org/works?search=foo&mailto={mailto}",
            context: ["mailto": ""]
        )
        XCTAssertFalse(expanded.contains("mailto="),
                       "empty mailto placeholder should be scrubbed, got \(expanded)")
    }

    func testExpandURLSubstitutesURLValueVerbatim() {
        // Keys ending in "Url" shouldn't be percent-encoded (they ARE the URL).
        let expanded = SiteAdapterRuntime.expandURL(
            "{subjectUrl}",
            context: ["subjectUrl": "https://book.douban.com/subject/1554675/"]
        )
        XCTAssertEqual(expanded, "https://book.douban.com/subject/1554675/")
    }

    // MARK: - Field features: wildcard join, postProcess, template

    func testExtractJSONJoinsWildcardArrays() throws {
        let adapter = try decodedAdapter("""
        {
          "id": "t", "schemaVersion": 1,
          "routes": { "r": {
            "url": "x",
            "extract": {
              "kind": "json", "itemsPath": "$",
              "fields": { "names": { "paths": ["people[*].name"], "separator": ", " } }
            }
          } }
        }
        """)
        let data = """
        {"people":[{"name":"Alice"},{"name":"Bob"}]}
        """.data(using: .utf8)!
        let rows = try SiteAdapterRuntime.extractJSON(route: adapter.routes["r"]!, data: data)
        XCTAssertEqual(rows.first?["names"], "Alice, Bob")
    }

    func testExtractJSONReconstructsInvertedIndexAbstract() throws {
        // OpenAlex-style inverted index: `abstract_inverted_index` maps each word
        // to the list of positions at which it appears. postProcess should
        // reconstruct the original sentence.
        let adapter = try decodedAdapter("""
        {
          "id": "t", "schemaVersion": 1,
          "routes": { "r": {
            "url": "x",
            "extract": {
              "kind": "json", "itemsPath": "$",
              "fields": {
                "abstract": { "paths": ["abstract_inverted_index"],
                              "postProcess": "reconstructInvertedIndex" }
              }
            }
          } }
        }
        """)
        let data = """
        {"abstract_inverted_index":{"The":[0],"cat":[2],"sat":[3],"brown":[1]}}
        """.data(using: .utf8)!
        let rows = try SiteAdapterRuntime.extractJSON(route: adapter.routes["r"]!, data: data)
        XCTAssertEqual(rows.first?["abstract"], "The brown cat sat")
    }

    func testExtractJSONRendersTemplateAndElidesWhenPathMissing() throws {
        let adapter = try decodedAdapter("""
        {
          "id": "t", "schemaVersion": 1,
          "routes": { "r": {
            "url": "x",
            "extract": {
              "kind": "json", "itemsPath": "$",
              "fields": {
                "pages": {
                  "template": "{biblio.first_page}-{biblio.last_page}",
                  "elideIfMissing": ["biblio.last_page"]
                }
              }
            }
          } }
        }
        """)
        let withBoth = """
        {"biblio":{"first_page":"101","last_page":"120"}}
        """.data(using: .utf8)!
        let withOnlyFirst = """
        {"biblio":{"first_page":"101"}}
        """.data(using: .utf8)!

        let rows1 = try SiteAdapterRuntime.extractJSON(route: adapter.routes["r"]!, data: withBoth)
        XCTAssertEqual(rows1.first?["pages"], "101-120")

        // elideIfMissing kicks in — should NOT produce "101-".
        let rows2 = try SiteAdapterRuntime.extractJSON(route: adapter.routes["r"]!, data: withOnlyFirst)
        XCTAssertNil(rows2.first?["pages"])
    }

    func testTransformStripDoiOrgPrefix() {
        XCTAssertEqual(
            SiteAdapterRuntime.applyTransform("https://doi.org/10.1234/XYZ", transform: "stripDoiOrgPrefix"),
            "10.1234/xyz"
        )
        XCTAssertEqual(
            SiteAdapterRuntime.applyTransform("10.5555/ABC", transform: "stripDoiOrgPrefix"),
            "10.5555/abc"
        )
    }

    // MARK: - OpenAlex adapter + row mapper

    func testRegistryFindsOpenAlexAdapter() {
        let adapter = SiteAdapterRegistry.shared.adapter(id: "openalex-work")
        XCTAssertNotNil(adapter)
        XCTAssertNotNil(adapter?.routes["byDoi"])
        XCTAssertNotNil(adapter?.routes["byTitle"])
    }

    func testOpenAlexByDoiFixtureExtractsCoreFields() throws {
        // Minimal but realistic OpenAlex /works/doi:... response shape.
        let fixture = """
        {
          "id": "https://openalex.org/W111",
          "doi": "https://doi.org/10.1234/xyz",
          "title": "Sample Paper",
          "publication_year": 2020,
          "type": "journal-article",
          "primary_location": {"source": {"display_name": "Journal of Tests"}},
          "biblio": {"volume": "5", "issue": "2", "first_page": "101", "last_page": "120"},
          "authorships": [
            {"author": {"display_name": "Alice Adams"}},
            {"author": {"display_name": "Bob Brown"}}
          ],
          "abstract_inverted_index": {"Hello":[0],"world":[1]},
          "open_access": {"is_oa": true, "oa_url": "https://example.com/pdf"},
          "cited_by_count": 42,
          "concepts": [{"display_name": "Biology", "score": 0.9}],
          "topics":   [{"display_name": "Ecology"}],
          "awards":   [{"funder_display_name": "NIH", "funder_award_id": "R01-123"}],
          "funders":  [{"display_name": "NIH"}]
        }
        """.data(using: .utf8)!

        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "openalex-work"),
              let route = adapter.routes["byDoi"] else {
            return XCTFail("bundled openalex-work adapter missing")
        }
        let rows = try SiteAdapterRuntime.extractJSON(route: route, data: fixture)
        XCTAssertEqual(rows.count, 1)
        guard let row = rows.first else { return }
        XCTAssertEqual(row["title"], "Sample Paper")
        XCTAssertEqual(row["doi"], "10.1234/xyz", "stripDoiOrgPrefix should normalize")
        XCTAssertEqual(row["year"], "2020")
        XCTAssertEqual(row["journal"], "Journal of Tests")
        XCTAssertEqual(row["pagesWhenBothPresent"], "101-120")
        XCTAssertEqual(row["authors"], "Alice Adams|Bob Brown")
        XCTAssertEqual(row["abstract"], "Hello world")
        XCTAssertEqual(row["isOpenAccess"], "true")
        XCTAssertEqual(row["oaUrl"], "https://example.com/pdf")
        XCTAssertEqual(row["citedByCount"], "42")
        XCTAssertEqual(row["conceptNames"], "Biology")
        XCTAssertEqual(row["topicNames"], "Ecology")
        XCTAssertEqual(row["grantFunders"], "NIH")
        XCTAssertEqual(row["grantAwards"], "R01-123")
    }

    func testOpenAlexRowMapperProducesReferenceAndEnrichment() {
        let row: [String: String] = [
            "openAlexId": "https://openalex.org/W111",
            "doi": "10.1234/xyz",
            "title": "Sample Paper",
            "year": "2020",
            "type": "journal-article",
            "journal": "Journal of Tests",
            "volume": "5", "issue": "2", "firstPage": "101", "lastPage": "120",
            "pagesWhenBothPresent": "101-120",
            "authors": "Alice Adams|Bob Brown",
            "abstract": "Hello world",
            "isOpenAccess": "true",
            "oaUrl": "https://example.com/pdf",
            "citedByCount": "42",
            "conceptNames": "Biology|Ecology",
            "topicNames": "Freshwater Ecology",
            "grantFunders": "NIH|NSF",
            "grantAwards": "R01-123|NSF-7"
        ]
        let (ref, enrichment) = MetadataFetcher.referenceAndEnrichmentFromOpenAlexRow(row)

        XCTAssertEqual(ref.title, "Sample Paper")
        XCTAssertEqual(ref.year, 2020)
        XCTAssertEqual(ref.journal, "Journal of Tests")
        XCTAssertEqual(ref.pages, "101-120")
        XCTAssertEqual(ref.doi, "10.1234/xyz")
        XCTAssertEqual(ref.abstract, "Hello world")
        XCTAssertEqual(ref.referenceType, .journalArticle)
        XCTAssertEqual(ref.metadataSource, .openAlex)
        XCTAssertEqual(ref.authors.count, 2)

        XCTAssertEqual(enrichment.keywords, ["Biology", "Ecology"])
        XCTAssertEqual(enrichment.topics, ["Freshwater Ecology"])
        XCTAssertTrue(enrichment.isOpenAccess)
        XCTAssertEqual(enrichment.oaUrl, "https://example.com/pdf")
        XCTAssertEqual(enrichment.citedByCount, 42)
        XCTAssertEqual(enrichment.fundingInfo, ["NIH (R01-123)", "NSF (NSF-7)"])
        XCTAssertEqual(enrichment.openAlexId, "https://openalex.org/W111")
    }

    // MARK: - JSON route (Douban new schema)

    func testExtractJSONWithDoubanSuggestNewSchema() throws {
        let payload = """
        [
          {"title":"高级水生生物学","url":"https://book.douban.com/subject/1554675/",
           "author_name":"刘建康 编","year":"1999","type":"b","id":"1554675"},
          {"title":"无关书","url":"https://book.douban.com/subject/9999/","type":"other"}
        ]
        """.data(using: .utf8)!

        let adapter = try decodedAdapter("""
        {
          "id": "test-douban",
          "schemaVersion": 1,
          "routes": {
            "search": {
              "url": "x",
              "extract": {
                "kind": "json",
                "itemsPath": "$",
                "itemFilter": {"field": "type", "equals": ["b","book"]},
                "fields": {
                  "title": {"paths":["title"]},
                  "subjectId": {"paths":["id"]},
                  "author": {"paths":["author_name","extra_attrs.author"]},
                  "year": {"paths":["year"], "transform":"prefix4Int"}
                }
              }
            }
          }
        }
        """)
        let route = adapter.routes["search"]!
        let rows = try SiteAdapterRuntime.extractJSON(route: route, data: payload)

        XCTAssertEqual(rows.count, 1, "filter should drop type=other")
        XCTAssertEqual(rows[0]["title"], "高级水生生物学")
        XCTAssertEqual(rows[0]["subjectId"], "1554675")
        XCTAssertEqual(rows[0]["author"], "刘建康 编")
        XCTAssertEqual(rows[0]["year"], "1999")
    }

    // MARK: - HTML route (Douban detail fixture)

    func testExtractHTMLWithDoubanDetailFixture() throws {
        let html = """
        <html><head>
          <meta property="book:isbn" content="9787030069870" />
        </head><body>
        <div id="info">
          <span><span class="pl"> 作者</span>: <a href="/a/">刘建康</a></span><br/>
          <span class="pl">出版社:</span> <a class="a_publisher">科学出版社</a><br/>
          <span class="pl">出版年:</span> 1999-3<br/>
          <span class="pl">页数:</span> 401<br/>
          <span class="pl">ISBN:</span> 9787030069870<br/>
        </div>
        <div id="link-report"><div class="intro"><p>内容简介文本。</p></div></div>
        </body></html>
        """
        // Use the real bundled Douban adapter so we're exercising production config.
        guard let adapter = SiteAdapterRegistry.shared.adapter(id: "douban-book"),
              let route = adapter.routes["detail"] else {
            return XCTFail("bundled douban-book adapter missing")
        }
        let row = try SiteAdapterRuntime.extractHTML(route: route, html: html)
        XCTAssertEqual(row["isbn"], "9787030069870")
        XCTAssertEqual(row["publisher"], "科学出版社")
        XCTAssertEqual(row["year"], "1999")
        XCTAssertEqual(row["pages"], "401")
        XCTAssertEqual(row["abstract"], "内容简介文本。")
    }

    // MARK: - Registry

    func testRegistryFindsBundledAdapter() {
        let adapter = SiteAdapterRegistry.shared.adapter(id: "douban-book")
        XCTAssertNotNil(adapter)
        XCTAssertEqual(adapter?.schemaVersion, 1)
        XCTAssertNotNil(adapter?.routes["search"])
        XCTAssertNotNil(adapter?.routes["detail"])
        XCTAssertFalse(adapter?.canary?.isEmpty ?? true)
    }

    /// Strict-enum invariant: every bundled adapter’s `transform` and
    /// `postProcess` values MUST be from the runtime-implemented set. This
    /// catches AI- or human-authored typos at CI time instead of letting
    /// unknown names silently degrade to identity functions at runtime.
    /// Keep the allowed sets in sync with SiteAdapterRuntime.applyTransform()
    /// and .applyPostProcess() plus Docs/adapter-schema.json.
    func testAllBundledAdaptersUseOnlyRegisteredTransformsAndPostProcesses() {
        let validTransforms: Set<String> = [
            "prefix4Int", "upper", "lower", "trim",
            "stripDoiOrgPrefix", "stripHtmlTags"
        ]
        let validPostProcesses: Set<String> = ["reconstructInvertedIndex"]
        let validRouteKinds: Set<SiteAdapterDefinition.RouteKind> = [.http, .webView]

        let ids = SiteAdapterRegistry.shared.allAdapterIDs()
        XCTAssertFalse(ids.isEmpty, "no bundled adapters discovered")

        for id in ids {
            guard let adapter = SiteAdapterRegistry.shared.adapter(id: id) else {
                XCTFail("failed to load adapter \(id)"); continue
            }
            for (routeName, route) in adapter.routes {
                if let kind = route.kind {
                    XCTAssertTrue(validRouteKinds.contains(kind),
                                  "\(id).\(routeName) uses unknown route kind \(kind)")
                }
                for (fieldName, field) in route.extract.fields {
                    if let t = field.transform {
                        XCTAssertTrue(validTransforms.contains(t),
                                      "\(id).\(routeName).\(fieldName) uses unknown transform '\(t)'. Allowed: \(validTransforms.sorted()).")
                    }
                    if let pp = field.postProcess {
                        XCTAssertTrue(validPostProcesses.contains(pp),
                                      "\(id).\(routeName).\(fieldName) uses unknown postProcess '\(pp)'. Allowed: \(validPostProcesses.sorted()).")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func decodedAdapter(_ json: String) throws -> SiteAdapterDefinition {
        try JSONDecoder().decode(SiteAdapterDefinition.self, from: json.data(using: .utf8)!)
    }
}

// MARK: - Canary Integration Harness (opt-in)

/// Hits the live upstream URLs declared in each adapter's `canary` array and
/// verifies that the current extraction rules still produce the expected
/// fields. This is the first line of defense against upstream schema drift.
///
/// Opt-in because tests shouldn't hit the network in normal CI:
/// set `SWIFTLIB_CANARY=1` in the environment to run it.
///
///   SWIFTLIB_CANARY=1 swift test --filter CanaryIntegrationTests
///
/// In CI, wire this up as a nightly GitHub Actions job. When it fails, the
/// adapter JSON (not Swift code) is what needs updating — see
/// `Docs/ADAPTERS.md` for the AI-assisted repair workflow.
final class CanaryIntegrationTests: XCTestCase {

    override class var defaultTestSuite: XCTestSuite {
        guard ProcessInfo.processInfo.environment["SWIFTLIB_CANARY"] == "1" else {
            return XCTestSuite(name: "CanaryIntegrationTests (skipped; set SWIFTLIB_CANARY=1)")
        }
        return super.defaultTestSuite
    }

    /// Iterates every bundled adapter and runs all of its declared canary
    /// cases. One test method covers every new adapter we ship — no need to
    /// remember to add per-source test methods.
    func testAllBundledAdaptersCanary() async throws {
        let ids = SiteAdapterRegistry.shared.allAdapterIDs()
        XCTAssertFalse(ids.isEmpty, "no adapters discovered")
        var failures: [String] = []
        for id in ids {
            guard let adapter = SiteAdapterRegistry.shared.adapter(id: id) else {
                failures.append("\(id): failed to load"); continue
            }
            guard let cases = adapter.canary, !cases.isEmpty else {
                print("⚠️ adapter \(id) has no canary cases; skipping")
                continue
            }
            for canary in cases {
                do {
                    try await runCanary(adapter: adapter, canary: canary)
                    print("✅ canary \(id) / \(canary.name) passed")
                } catch {
                    failures.append("\(id) / \(canary.name): \(error)")
                }
            }
        }
        if !failures.isEmpty {
            XCTFail("Canary failures:\n" + failures.joined(separator: "\n"))
        }
    }

    private func runCanary(
        adapter: SiteAdapterDefinition,
        canary: SiteAdapterDefinition.CanaryCase
    ) async throws {
        // --- Search route ---
        //
        // Routes are looked up under the adapter's preferred route name; we
        // try common ones in priority order so one harness covers every
        // adapter without per-source wiring. `searchQuery` is the legacy
        // shorthand and auto-populates all common placeholder keys so a route
        // with `{doi}` / `{title}` / `{query}` / `{isbn}` "just works".
        let searchRouteName = canary.route
            ?? ["search", "byDoi", "byTitle", "byTitleMatch", "byIsbn"]
                .first(where: { adapter.routes[$0] != nil })
        if let routeName = searchRouteName, let searchRoute = adapter.routes[routeName] {
            // Base context covers most conventional placeholder names.
            var ctx: [String: String] = [:]
            if let q = canary.searchQuery {
                ctx = ["query": q, "doi": q, "title": q, "isbn": q, "pmid": q, "arxivId": q]
            }
            // Explicit context always takes precedence.
            for (k, v) in canary.context ?? [:] { ctx[k] = v }
            // Always provide an (optional) mailto so URLs with `{mailto}` don't leak braces.
            ctx["mailto"] = ctx["mailto"] ?? ""
            ctx["perPage"] = ctx["perPage"] ?? "5"

            let urlStr = SiteAdapterRuntime.expandURL(searchRoute.url, context: ctx)
            guard let url = URL(string: urlStr) else {
                return XCTFail("bad search URL for canary: \(canary.name) → \(urlStr)")
            }
            let (data, _) = try await URLSession.shared.data(for: buildRequest(url: url, headers: searchRoute.headers))
            // Pass `ctx` through so adapters with templated itemsPaths
            // (e.g. Open Library's `ISBN:{isbn}`) resolve correctly.
            let rows = try SiteAdapterRuntime.extractJSON(route: searchRoute, data: data, context: ctx)
            XCTAssertFalse(rows.isEmpty, "canary \(canary.name): search returned 0 rows")
            if let expect = canary.expectSearch, let row = rows.first {
                for (k, v) in expect {
                    XCTAssertEqual(row[k], v, "canary \(canary.name): search.\(k) mismatch (actual=\(row[k] ?? "nil"))")
                }
            }
        }

        // --- Detail route ---
        if let subjectUrl = canary.subjectUrl, let detailRoute = adapter.routes["detail"] {
            guard let url = URL(string: subjectUrl) else {
                return XCTFail("bad detail URL for canary: \(canary.name)")
            }
            let (data, _) = try await URLSession.shared.data(for: buildRequest(url: url, headers: detailRoute.headers))
            guard let html = String(data: data, encoding: .utf8) else {
                return XCTFail("canary \(canary.name): detail non-UTF8 body")
            }
            let row = try SiteAdapterRuntime.extractHTML(route: detailRoute, html: html)
            if let expect = canary.expectDetail {
                for (k, v) in expect {
                    XCTAssertEqual(row[k], v, "canary \(canary.name): detail.\(k) mismatch (actual=\(row[k] ?? "nil"))")
                }
            }
        }
    }

    private func buildRequest(url: URL, headers: [String: String]?) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("SwiftLib/canary", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers ?? [:] { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 20
        return req
    }
}
