import Foundation
import Network
import SwiftLibCore

/// Lightweight HTTP server that serves the Word Add-in static files and
/// exposes REST API endpoints consumed by the taskpane / commands / dialog JS.
///
/// Runs on http://127.0.0.1:23858 – the same origin referenced by the Add-in
/// manifest.  Uses NWListener (Network framework) to avoid external deps.
final class WordAddinServer {
    static let shared = WordAddinServer()
    static let port: UInt16 = 23858

    private var listener: NWListener?
    private(set) var isRunning = false

    private let queue = DispatchQueue(label: "WordAddinServer", qos: .userInitiated)
    private let focusBounceQueue = DispatchQueue(label: "WordAddinServer.FocusBounce", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    print("[WordAddinServer] listening on 127.0.0.1:\(Self.port)")
                case .failed(let err):
                    print("[WordAddinServer] listener failed: \(err)")
                    self?.isRunning = false
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("[WordAddinServer] failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connection

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveHTTP(conn)
    }

    private func receiveHTTP(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            if let error {
                print("[WordAddinServer] recv error: \(error)")
                conn.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                if isComplete { conn.cancel() }
                return
            }
            guard let raw = String(data: data, encoding: .utf8) else {
                self.sendResponse(conn, status: 400, body: "Bad Request")
                return
            }
            self.route(conn, raw: raw)
        }
    }

    // MARK: - Routing

    private func route(_ conn: NWConnection, raw: String) {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(conn, status: 400, body: "Bad Request"); return
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendResponse(conn, status: 400, body: "Bad Request"); return
        }
        let method = String(parts[0])
        let rawPath = String(parts[1])

        // Extract body for POST
        let body: Data? = {
            guard method == "POST", let range = raw.range(of: "\r\n\r\n") else { return nil }
            let bodyStr = String(raw[range.upperBound...])
            return bodyStr.data(using: .utf8)
        }()

        // Split path and query
        let (path, queryString) = splitPathQuery(rawPath)

        switch (method, path) {
        // API endpoints
        case ("GET", "/api/search"):
            handleSearch(conn, query: queryString)
        case ("GET", "/api/references"):
            handleReferences(conn, query: queryString)
        case ("GET", "/api/cite-items"):
            handleCiteItems(conn, query: queryString)
        case ("GET", "/api/styles"):
            handleStyles(conn)
        case ("GET", "/api/csl"):
            handleCSL(conn, query: queryString)
        case ("GET", "/api/locale"):
            handleLocale(conn, query: queryString)
        case ("POST", "/api/render-document"):
            handleRenderDocument(conn, body: body)
        case ("POST", "/api/styles/import"):
            handleStyleImport(conn, body: body)
        case ("POST", "/api/styles/delete"):
            handleStyleDelete(conn, body: body)
        case ("POST", "/api/perf-log"):
            handlePerfLog(conn, body: body)
        case ("POST", "/api/wps/focus-bounce"):
            handleWPSFocusBounce(conn)
        case ("OPTIONS", _):
            handleOptions(conn)
        case ("GET", _):
            serveStaticFile(conn, path: path)
        default:
            sendResponse(conn, status: 404, body: "Not Found")
        }
    }

    // MARK: - API: Search

    private func handleSearch(_ conn: NWConnection, query: String) {
        let params = parseQuery(query)
        guard let q = params["q"], !q.isEmpty else {
            sendJSON(conn, status: 400, json: ["error": "missing q parameter"]); return
        }
        let limit = Int(params["limit"] ?? "") ?? 25
        do {
            let refs = try AppDatabase.shared.searchReferences(query: q, limit: limit)
            let arr = refs.map { referenceToJSON($0) }
            sendJSONArray(conn, arr)
        } catch {
            sendJSON(conn, status: 500, json: ["error": error.localizedDescription])
        }
    }

    // MARK: - API: References by IDs

    private func handleReferences(_ conn: NWConnection, query: String) {
        let params = parseQuery(query)
        guard let idsStr = params["ids"], !idsStr.isEmpty else {
            sendJSON(conn, status: 400, json: ["error": "missing ids parameter"]); return
        }
        let ids = idsStr.split(separator: ",").compactMap { Int64($0) }
        do {
            let refs = try AppDatabase.shared.fetchReferences(ids: ids)
            let arr = refs.map { referenceToJSON($0) }
            sendJSONArray(conn, arr)
        } catch {
            sendJSON(conn, status: 500, json: ["error": error.localizedDescription])
        }
    }

    // MARK: - API: CSL JSON items

    private func handleCiteItems(_ conn: NWConnection, query: String) {
        let params = parseQuery(query)
        guard let idsStr = params["ids"], !idsStr.isEmpty else {
            sendJSON(conn, status: 400, json: ["error": "missing ids parameter"]); return
        }
        let ids = idsStr.split(separator: ",").compactMap { Int64($0) }
        do {
            let refs = try AppDatabase.shared.fetchReferences(ids: ids)
            // Return an array so taskpane.js can iterate with for...of.
            // Each object includes _swiftlibRefId (the numeric DB id as a string)
            // which the client uses as the dictionary key for the embedded snapshot.
            let arr: [[String: Any]] = refs.compactMap { ref -> [String: Any]? in
                guard let id = ref.id else { return nil }
                var item = ref.cslJSONObject()
                item["_swiftlibRefId"] = String(id)
                return item
            }
            sendJSONArray(conn, arr)
        } catch {
            sendJSON(conn, status: 500, json: ["error": error.localizedDescription])
        }
    }

    // MARK: - API: Styles

    private func handleStyles(_ conn: NWConnection) {
        let styles = CSLManager.shared.availableStyles()
        let arr: [[String: Any]] = styles.map { s in
            [
                "id": s.id,
                "title": s.title,
                "builtin": s.isBuiltin,
                "citationKind": s.citationKind.rawValue,
            ]
        }
        sendJSONArray(conn, arr)
    }

    // MARK: - API: CSL XML (for client-side citeproc)

    private func handleCSL(_ conn: NWConnection, query: String) {
        let params = parseQuery(query)
        guard let styleId = params["id"], !styleId.isEmpty else {
            sendResponse(conn, status: 400, body: "missing id parameter"); return
        }

        // 1. Try bundled CSL files
        let stem = CiteprocJSCorePool.bundledCSLStem(for: styleId) ?? styleId
        let subdirs = ["WordAddin/CSL", "CSL"]
        for subdir in subdirs {
            for bundle in [Bundle.swiftLibCoreBundle, Bundle.main].compactMap({ $0 }) {
                if let url = bundle.url(forResource: stem, withExtension: "csl", subdirectory: subdir),
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    sendResponse(conn, status: 200, body: content, contentType: "application/xml")
                    return
                }
            }
        }

        // 2. Try user-imported CSL via CSLManager
        if let data = CSLManager.shared.cslXmlData(forStyleId: styleId),
           let content = String(data: data, encoding: .utf8) {
            sendResponse(conn, status: 200, body: content, contentType: "application/xml")
            return
        }

        sendResponse(conn, status: 404, body: "CSL style not found: \(styleId)")
    }

    // MARK: - API: Locale XML (for client-side citeproc)

    private func handleLocale(_ conn: NWConnection, query: String) {
        let params = parseQuery(query)
        let lang = params["id"] ?? "en-US"
        let normalized = lang.replacingOccurrences(of: "_", with: "-")
        let stem = "locales-\(normalized)"

        let subdirs = ["WordAddin/locales", "locales"]
        for subdir in subdirs {
            for bundle in [Bundle.swiftLibCoreBundle, Bundle.main].compactMap({ $0 }) {
                if let url = bundle.url(forResource: stem, withExtension: "xml", subdirectory: subdir),
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    sendResponse(conn, status: 200, body: content, contentType: "application/xml")
                    return
                }
            }
        }

        // Fallback to en-US if requested locale not found
        if normalized.lowercased() != "en-us" {
            handleLocale(conn, query: "id=en-US")
            return
        }

        sendResponse(conn, status: 404, body: "Locale not found: \(lang)")
    }

    // MARK: - API: Render Document

    private func handleRenderDocument(_ conn: NWConnection, body: Data?) {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            sendJSON(conn, status: 400, json: ["error": "invalid request body"]); return
        }
        guard let styleId = json["style"] as? String else {
            sendJSON(conn, status: 400, json: ["error": "missing style"]); return
        }
        guard let citationsRaw = json["citations"] as? [[String: Any]] else {
            sendJSON(conn, status: 400, json: ["error": "missing citations"]); return
        }

        // Client may send embedded CSL-JSON snapshots keyed by docItemKey ("lib:<id>" etc.)
        let providedItems = json["items"] as? [String: [String: Any]]
        let includeBibliography = (json["includeBibliography"] as? Bool) ?? true

        if citationsRaw.isEmpty {
            sendJSONObject(conn, [
                "citationTexts": [String: String](),
                "bibliographyText": "",
                "superscriptCitationIDs": [String](),
            ])
            return
        }

        // Collect all numeric reference IDs mentioned in the citations
        var allRefIDs = Set<Int64>()
        for c in citationsRaw {
            if let ids = c["ids"] as? [Any] {
                for rawId in ids {
                    if let n = rawId as? Int64 { allRefIDs.insert(n) }
                    else if let n = rawId as? Int { allRefIDs.insert(Int64(n)) }
                    else if let s = rawId as? String, let n = Int64(s) { allRefIDs.insert(n) }
                }
            }
        }

        // Build CSL items array:
        // 1. Always query the live DB to get up-to-date data for items that still exist.
        // 2. For IDs that are no longer in the DB (deleted from library), fall back to
        //    the embedded snapshot sent by the client (providedItems). These are "orphan" items.
        // 3. Return orphanIds in the response so the UI can show a relink banner.
        var cslItems: [[String: Any]] = []
        var orphanStringIDs: [String] = []
        do {
            let refs = try AppDatabase.shared.fetchReferences(ids: Array(allRefIDs))
            let fetchedIDs = Set(refs.compactMap { $0.id })
            cslItems = refs.compactMap { ref -> [String: Any]? in
                guard ref.id != nil else { return nil }
                return ref.cslJSONObject()
            }
            // Detect orphan IDs: referenced in the document but missing from the DB
            let missingIDs = allRefIDs.subtracting(fetchedIDs)
            if !missingIDs.isEmpty {
                orphanStringIDs = missingIDs.sorted().map { String($0) }
                // Try to fill orphan items from the embedded client snapshot
                let snapshotValues = providedItems?.values.map { $0 } ?? []
                // Build a lookup: csl id → item (the embedded items have id = String(refId))
                var snapshotByID: [String: [String: Any]] = [:]
                for item in snapshotValues {
                    if let itemId = item["id"] as? String { snapshotByID[itemId] = item }
                }
                for orphanID in orphanStringIDs {
                    if let fallback = snapshotByID[orphanID] {
                        cslItems.append(fallback)
                    }
                    // If no embedding is available, the render will throw with a clear message
                }
            }
        } catch {
            sendJSON(conn, status: 500, json: ["error": error.localizedDescription]); return
        }

        // Build citation tuples
        let citations: [(id: String, itemIDs: [String], position: Int, citationItems: [[String: Any]]?)] = citationsRaw.compactMap { c in
            guard let key = c["key"] as? String else { return nil }
            let position = c["position"] as? Int ?? 0
            let ids: [String] = (c["ids"] as? [Any])?.compactMap { rawId -> String? in
                if let n = rawId as? Int64 { return String(n) }
                if let n = rawId as? Int { return String(n) }
                if let s = rawId as? String { return s }
                return nil
            } ?? []
            let citationItems = c["citationItems"] as? [[String: Any]]
            return (id: key, itemIDs: ids, position: position, citationItems: citationItems)
        }

        // Render using pool (thread-safe).
        // Use an explicit do-catch so we can produce specific error messages:
        //   • nil from withEngine  → style XML not found / engine init failed
        //   • thrown EngineError   → rendering failure (e.g. missing items not covered by snapshot)
        let renderResult: (citationTexts: [String: String], bibliographyText: String, superscriptIDs: Set<String>, citationFormatting: CitationTextFormatting?)
        do {
            guard let r = try CiteprocJSCorePool.shared.withEngine(forStyleId: styleId, { engine in
                engine.setItems(cslItems)
                return try engine.renderDocument(citations: citations, includeBibliography: includeBibliography)
            }) else {
                sendJSON(conn, status: 500, json: ["error": "无法加载引文样式 \(styleId)，请在样式管理中重新导入该样式。"]); return
            }
            renderResult = r
        } catch {
            // engine.renderDocument threw — surface the real message (e.g. missing library items)
            sendJSON(conn, status: 422, json: [
                "error": error.localizedDescription,
                "orphanIds": orphanStringIDs,
            ]); return
        }

        let (citationTexts, bibliographyText, superscriptIDs, citationFormatting) = renderResult
        var response: [String: Any] = [
            "citationTexts": citationTexts,
            "bibliographyText": bibliographyText,
            "superscriptCitationIDs": Array(superscriptIDs),
        ]
        if !orphanStringIDs.isEmpty {
            response["orphanIds"] = orphanStringIDs
        }
        if let fmt = citationFormatting {
            var fmtDict: [String: Any] = [:]
            if let v = fmt.superscript { fmtDict["superscript"] = v }
            if let v = fmt.subscripted { fmtDict["subscript"] = v }
            if let v = fmt.bold { fmtDict["bold"] = v }
            if let v = fmt.italic { fmtDict["italic"] = v }
            if let v = fmt.underline { fmtDict["underline"] = v }
            if let v = fmt.smallCaps { fmtDict["smallCaps"] = v }
            response["citationFormatting"] = fmtDict
        }
        sendJSONObject(conn, response)
    }

    // MARK: - API: Import style

    private func handleStyleImport(_ conn: NWConnection, body: Data?) {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            sendJSON(conn, status: 400, json: ["error": "invalid request body"]); return
        }
        let id = json["id"] as? String ?? UUID().uuidString
        let title = json["title"] as? String ?? "Untitled Style"

        if let xmlString = (json["xmlData"] as? String) ?? (json["xml"] as? String),
           let xmlData = xmlString.data(using: .utf8) {
            do {
                try CSLManager.shared.importCSL(id: id, title: title, xmlData: xmlData)
                sendJSON(conn, status: 200, json: ["success": true, "title": title])
            } catch {
                sendJSON(conn, status: 500, json: ["error": error.localizedDescription])
            }
        } else {
            sendJSON(conn, status: 400, json: ["error": "missing xmlData"])
        }
    }

    // MARK: - API: Delete style

    private func handleStyleDelete(_ conn: NWConnection, body: Data?) {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let id = json["id"] as? String else {
            sendJSON(conn, status: 400, json: ["error": "missing id"]); return
        }
        do {
            try CSLManager.shared.deleteImportedCSL(id: id)
            sendJSON(conn, status: 200, json: ["success": true])
        } catch {
            sendJSON(conn, status: 400, json: ["error": error.localizedDescription])
        }
    }

    // MARK: - Performance Logging (from WPS add-in)

    private func handlePerfLog(_ conn: NWConnection, body: Data?) {
        if let body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let lines = json["lines"] as? [String] {
            print("──── WPS Add-in Performance ────")
            for line in lines { print(line) }
            print("────────────────────────────────")
        }
        sendJSON(conn, status: 200, json: ["ok": true])
    }

    // MARK: - WPS focus bounce (return keyboard focus to WPS document after task pane action)
    // Briefly activates SwiftLib itself, then immediately re-activates WPS.
    // This causes macOS to reassign FirstResponder from the task pane WebView
    // back to the WPS document area without any visible app-switching to the user.

    private func handleWPSFocusBounce(_ conn: NWConnection) {
        focusBounceQueue.async { [weak self] in
            guard let self else { conn.cancel(); return }
            let wpsID = "com.kingsoft.wpsoffice.mac"
            // Use "System Events" as the invisible bounce target — it is a macOS background
            // daemon, always running, has no visible UI, so the user sees nothing flash.
            let script = """
                tell application "System Events" to activate
                delay 0.05
                do shell script "/usr/bin/open -b \(wpsID)"
                """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {}
            self.sendJSON(conn, status: 200, json: ["ok": true])
        }
    }

    // MARK: - CORS Preflight

    private func handleOptions(_ conn: NWConnection) {
        let header = "HTTP/1.1 204 No Content\r\n"
            + "Access-Control-Allow-Origin: *\r\n"
            + "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            + "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
            + "Access-Control-Max-Age: 86400\r\n"
            + "Content-Length: 0\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        conn.send(content: header.data(using: .utf8)!, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - Static File Serving

    private func serveStaticFile(_ conn: NWConnection, path: String) {
        let cleanPath = path == "/" ? "/taskpane.html" : path

        // Programmatic placeholder icons
        if cleanPath == "/icon-16.png" || cleanPath == "/icon-32.png" || cleanPath == "/icon-80.png" {
            let size: Int
            switch cleanPath {
            case "/icon-16.png": size = 16
            case "/icon-32.png": size = 32
            default: size = 80
            }
            let pngData = Self.generatePlaceholderIcon(size: size)
            sendRawResponse(conn, status: 200, contentType: "image/png", body: pngData)
            return
        }

        // Map URL path → resource path
        let resourcePath: String
        switch cleanPath {
        case "/taskpane.html", "/taskpane.js",
             "/commands.html", "/commands.js",
             "/dialog.html", "/dialog.js",
             "/swiftlib-shared.js", "/swiftlib-guard-cleanup.js":
            resourcePath = "Resources/WordAddin\(cleanPath)"
        case "/citeproc-bundle.js", "/dist/citeproc-bundle.js":
            resourcePath = "Resources/WordAddin/dist/citeproc-bundle.js"
        default:
            if cleanPath.hasPrefix("/wps/") {
                // WPS add-in files: /wps/foo.js → Resources/WPSAddin/foo.js
                let wpsRelative = String(cleanPath.dropFirst("/wps/".count))
                resourcePath = "Resources/WPSAddin/\(wpsRelative)"
            } else if cleanPath.hasPrefix("/locales/") {
                resourcePath = "Resources/WordAddin\(cleanPath)"
            } else if cleanPath.hasPrefix("/CSL/") {
                resourcePath = "Resources/WordAddin\(cleanPath)"
            } else {
                sendResponse(conn, status: 404, body: "Not Found"); return
            }
        }

        // Look up in SwiftLibCore's bundle
        let resourceName = (resourcePath as NSString).deletingPathExtension
        let ext = (resourcePath as NSString).pathExtension

        guard let url = Bundle.swiftLibCoreBundle.url(forResource: resourceName, withExtension: ext.isEmpty ? nil : ext) else {
            sendResponse(conn, status: 404, body: "Not Found"); return
        }

        guard let fileData = try? Data(contentsOf: url) else {
            sendResponse(conn, status: 500, body: "Internal Server Error"); return
        }

        let contentType = mimeType(for: cleanPath)
        sendRawResponse(conn, status: 200, contentType: contentType, body: fileData)
    }

    // MARK: - Response helpers

    private func sendResponse(_ conn: NWConnection, status: Int, body: String, contentType: String = "text/plain; charset=utf-8") {
        let data = body.data(using: .utf8) ?? Data()
        sendRawResponse(conn, status: status, contentType: contentType, body: data)
    }

    private func sendJSON(_ conn: NWConnection, status: Int, json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else {
            sendResponse(conn, status: 500, body: "JSON serialization error"); return
        }
        sendRawResponse(conn, status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    private func sendJSONArray(_ conn: NWConnection, _ array: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: array) else {
            sendResponse(conn, status: 500, body: "JSON serialization error"); return
        }
        sendRawResponse(conn, status: 200, contentType: "application/json; charset=utf-8", body: data)
    }

    private func sendJSONObject(_ conn: NWConnection, _ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            sendResponse(conn, status: 500, body: "JSON serialization error"); return
        }
        sendRawResponse(conn, status: 200, contentType: "application/json; charset=utf-8", body: data)
    }

    private func sendRawResponse(_ conn: NWConnection, status: Int, contentType: String, body: Data) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }
        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"
        var responseData = header.data(using: .utf8)!
        responseData.append(body)
        conn.send(content: responseData, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - Reference → JSON

    private func referenceToJSON(_ ref: Reference) -> [String: Any] {
        var dict: [String: Any] = [
            "id": ref.id ?? 0,
            "title": ref.title,
            "authors": ref.authors.map(\.displayName).joined(separator: ", "),
            "referenceType": ref.referenceType.rawValue,
        ]
        if let v = ref.year { dict["year"] = v }
        if let v = ref.journal { dict["journal"] = v }
        if let v = ref.volume { dict["volume"] = v }
        if let v = ref.issue { dict["issue"] = v }
        if let v = ref.pages { dict["pages"] = v }
        if let v = ref.doi { dict["doi"] = v }
        if let v = ref.url { dict["url"] = v }
        if let v = ref.abstract { dict["abstract"] = v }
        if let v = ref.siteName { dict["siteName"] = v }
        return dict
    }

    // MARK: - Utilities

    private func splitPathQuery(_ raw: String) -> (path: String, query: String) {
        if let idx = raw.firstIndex(of: "?") {
            return (String(raw[..<idx]), String(raw[raw.index(after: idx)...]))
        }
        return (raw, "")
    }

    private func parseQuery(_ qs: String) -> [String: String] {
        guard !qs.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in qs.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let key = kv.first else { continue }
            let value = kv.count > 1 ? String(kv[1]) : ""
            result[String(key)] = value.removingPercentEncoding ?? value
        }
        return result
    }

    private func mimeType(for path: String) -> String {
        if path.hasSuffix(".html") { return "text/html; charset=utf-8" }
        if path.hasSuffix(".js") { return "application/javascript; charset=utf-8" }
        if path.hasSuffix(".css") { return "text/css; charset=utf-8" }
        if path.hasSuffix(".json") { return "application/json; charset=utf-8" }
        if path.hasSuffix(".xml") { return "application/xml; charset=utf-8" }
        if path.hasSuffix(".png") { return "image/png" }
        if path.hasSuffix(".svg") { return "image/svg+xml" }
        return "application/octet-stream"
    }

    /// Generates a minimal valid PNG with a colored circle as a placeholder icon.
    /// Uses raw PNG encoding (no AppKit/CoreGraphics dependency) to stay lightweight.
    private static func generatePlaceholderIcon(size: Int) -> Data {
        // Minimal uncompressed RGBA PNG
        let width = size
        let height = size
        let centerX = Double(width) / 2.0
        let centerY = Double(height) / 2.0
        let radius = Double(min(width, height)) / 2.0 - 1.0

        // Build raw pixel rows (filter byte + RGBA per pixel)
        var rawPixels = Data()
        for y in 0..<height {
            rawPixels.append(0) // filter: None
            for x in 0..<width {
                let dx = Double(x) - centerX + 0.5
                let dy = Double(y) - centerY + 0.5
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist <= radius {
                    // SwiftLib blue: #3B82F6
                    rawPixels.append(contentsOf: [0x3B, 0x82, 0xF6, 0xFF])
                } else {
                    rawPixels.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
                }
            }
        }

        // Deflate-store (uncompressed deflate blocks)
        let deflated = Self.deflateStore(rawPixels)

        var png = Data()
        // PNG signature
        png.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        func appendChunk(_ type: [UInt8], _ data: Data) {
            var chunk = Data()
            let length = UInt32(data.count)
            chunk.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })
            chunk.append(contentsOf: type)
            chunk.append(data)
            var crcData = Data(type)
            crcData.append(data)
            let crc = Self.crc32(crcData)
            chunk.append(contentsOf: withUnsafeBytes(of: crc.bigEndian) { Array($0) })
            png.append(chunk)
        }

        // IHDR
        var ihdr = Data()
        ihdr.append(contentsOf: withUnsafeBytes(of: UInt32(width).bigEndian) { Array($0) })
        ihdr.append(contentsOf: withUnsafeBytes(of: UInt32(height).bigEndian) { Array($0) })
        ihdr.append(8)  // bit depth
        ihdr.append(6)  // color type: RGBA
        ihdr.append(0)  // compression
        ihdr.append(0)  // filter
        ihdr.append(0)  // interlace
        appendChunk([0x49, 0x48, 0x44, 0x52], ihdr)

        // IDAT
        appendChunk([0x49, 0x44, 0x41, 0x54], deflated)

        // IEND
        appendChunk([0x49, 0x45, 0x4E, 0x44], Data())

        return png
    }

    /// Wraps raw data in a valid zlib stream using uncompressed deflate blocks.
    private static func deflateStore(_ input: Data) -> Data {
        var output = Data()
        // zlib header (CM=8, CINFO=7, no dict, FLEVEL=0)
        output.append(contentsOf: [0x78, 0x01])

        let maxBlock = 65535
        var offset = 0
        while offset < input.count {
            let remaining = input.count - offset
            let blockSize = min(remaining, maxBlock)
            let isLast: UInt8 = (offset + blockSize >= input.count) ? 1 : 0
            output.append(isLast)
            let len = UInt16(blockSize)
            let nlen = ~len
            output.append(contentsOf: withUnsafeBytes(of: len.littleEndian) { Array($0) })
            output.append(contentsOf: withUnsafeBytes(of: nlen.littleEndian) { Array($0) })
            output.append(input[offset..<(offset + blockSize)])
            offset += blockSize
        }

        // Adler-32 checksum
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in input {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let adler = (b << 16) | a
        output.append(contentsOf: withUnsafeBytes(of: adler.bigEndian) { Array($0) })

        return output
    }

    /// CRC-32 used by PNG chunks.
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = Self.crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c >>= 1
                }
            }
            return c
        }
    }()
}

// MARK: - Bundle helper

extension Bundle {
    /// The resource bundle for SwiftLibCore (contains WordAddin resources).
    static let swiftLibCoreBundle: Bundle = {
        #if SWIFT_PACKAGE
        // In SPM, `Bundle.module` is only available within the target that defines it.
        // We look for the SwiftLibCore resource bundle by name.
        // SPM naming convention: {PackageName}_{TargetName}
        let bundleNames = ["SwiftLib_SwiftLibCore", "SwiftLibCore_SwiftLibCore"]
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
            // When running via `swift run`, the bundle sits next to the executable
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }

        for bundleName in bundleNames {
            for candidate in candidates {
                let bundlePath = candidate.appendingPathComponent(bundleName + ".bundle")
                if let bundle = Bundle(url: bundlePath) {
                    return bundle
                }
            }
        }
        // Fallback: try SwiftLibCore's own module bundle
        // This works when the code runs inside SwiftLibCore's own test target
        // or when the bundle is embedded in the app.
        for bundle in Bundle.allBundles {
            for bundleName in bundleNames {
                if bundle.bundlePath.contains(bundleName) {
                    return bundle
                }
            }
        }
        return Bundle.main
        #else
        return Bundle.main
        #endif
    }()
}
