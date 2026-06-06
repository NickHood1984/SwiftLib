import Foundation

public enum CitationPreflightSeverity: String, Codable, Sendable {
    case critical
    case warning
}

public struct CitationPreflightIssue: Codable, Equatable, Sendable {
    public let severity: CitationPreflightSeverity
    public let referenceID: String?
    public let referenceTitle: String?
    public let citationID: String?
    public let fieldKey: String?
    public let displayName: String
    public let message: String

    public init(
        severity: CitationPreflightSeverity,
        referenceID: String? = nil,
        referenceTitle: String? = nil,
        citationID: String? = nil,
        fieldKey: String? = nil,
        displayName: String,
        message: String
    ) {
        self.severity = severity
        self.referenceID = referenceID
        self.referenceTitle = referenceTitle
        self.citationID = citationID
        self.fieldKey = fieldKey
        self.displayName = displayName
        self.message = message
    }
}

public struct CitationPreflightReport: Codable, Equatable, Sendable {
    public let styleID: String
    public let issues: [CitationPreflightIssue]

    public init(styleID: String, issues: [CitationPreflightIssue]) {
        self.styleID = styleID
        self.issues = issues
    }

    public var criticalIssues: [CitationPreflightIssue] {
        issues.filter { $0.severity == .critical }
    }

    public var warningIssues: [CitationPreflightIssue] {
        issues.filter { $0.severity == .warning }
    }

    public var isBlocked: Bool {
        !criticalIssues.isEmpty
    }

    public var blockingMessage: String {
        guard isBlocked else { return "" }
        let details = criticalIssues.prefix(6).map { issue -> String in
            let refLabel: String
            if let referenceID = issue.referenceID {
                refLabel = "文献 \(referenceID)"
            } else if let citationID = issue.citationID {
                refLabel = "引文 \(citationID)"
            } else {
                refLabel = "引文"
            }
            return "\(refLabel)：\(issue.message)"
        }
        let suffix = criticalIssues.count > details.count
            ? "\n另有 \(criticalIssues.count - details.count) 个问题。"
            : ""
        return "当前 CSL 样式无法可靠生成该引文，请先补全字段后再插入。\n"
            + details.joined(separator: "\n")
            + suffix
    }

    public func jsonObject() -> [String: Any] {
        [
            "style": styleID,
            "blocked": isBlocked,
            "message": blockingMessage,
            "issues": issues.map { issue in
                var object: [String: Any] = [
                    "severity": issue.severity.rawValue,
                    "displayName": issue.displayName,
                    "message": issue.message,
                ]
                if let value = issue.referenceID { object["referenceID"] = value }
                if let value = issue.referenceTitle { object["referenceTitle"] = value }
                if let value = issue.citationID { object["citationID"] = value }
                if let value = issue.fieldKey { object["fieldKey"] = value }
                return object
            },
        ]
    }
}

public enum CitationPreflightValidator {
    public static func validate(
        styleID: String,
        references: [Reference],
        citationClusters: [CitationDocumentCluster] = [],
        citationTexts: [String: String] = [:],
        bibliographyText: String? = nil,
        includeBibliography: Bool = false
    ) -> CitationPreflightReport {
        let referencedIDs = Set(citationClusters.flatMap(\.itemIDs))
        let referencesToCheck: [Reference]
        if referencedIDs.isEmpty {
            referencesToCheck = references
        } else {
            referencesToCheck = references.filter { ref in
                ref.id.map { referencedIDs.contains(String($0)) } ?? true
            }
        }

        var issues: [CitationPreflightIssue] = []
        for reference in referencesToCheck {
            let refID = reference.id.map(String.init)
            let refTitle = reference.title.swiftlib_nilIfBlank
            for fieldIssue in reference.cslFieldIssues {
                let severity = severity(for: fieldIssue.severity)
                issues.append(CitationPreflightIssue(
                    severity: severity,
                    referenceID: refID,
                    referenceTitle: refTitle,
                    fieldKey: fieldIssue.fieldKey,
                    displayName: fieldIssue.displayName,
                    message: message(for: fieldIssue, severity: severity)
                ))
            }
        }

        for cluster in citationClusters {
            let rendered = citationTexts[cluster.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rendered.isEmpty {
                issues.append(CitationPreflightIssue(
                    severity: .critical,
                    citationID: cluster.id,
                    displayName: "引文文本",
                    message: "当前样式没有生成引文文本。"
                ))
            } else if let fragment = invalidRenderedFragment(in: rendered) {
                issues.append(CitationPreflightIssue(
                    severity: .critical,
                    citationID: cluster.id,
                    displayName: "引文文本",
                    message: "生成结果包含异常片段 \(fragment)。"
                ))
            }
        }

        if includeBibliography, !citationClusters.isEmpty {
            let bibliography = bibliographyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if bibliography.isEmpty {
                issues.append(CitationPreflightIssue(
                    severity: .critical,
                    displayName: "参考文献表",
                    message: "当前样式没有生成参考文献条目。"
                ))
            } else if let fragment = invalidRenderedFragment(in: bibliography) {
                issues.append(CitationPreflightIssue(
                    severity: .critical,
                    displayName: "参考文献表",
                    message: "参考文献条目包含异常片段 \(fragment)。"
                ))
            }
        }

        return CitationPreflightReport(styleID: styleID, issues: issues)
    }

    private static func severity(for issueSeverity: CSLFieldSeverity) -> CitationPreflightSeverity {
        switch issueSeverity {
        case .critical: return .critical
        case .recommended: return .warning
        }
    }

    private static func message(
        for issue: CSLFieldIssue,
        severity: CitationPreflightSeverity
    ) -> String {
        switch severity {
        case .critical:
            return "缺少\(issue.displayName)，当前 CSL 样式无法可靠生成该文献。"
        case .warning:
            return "缺少\(issue.displayName)，生成结果可能不完整。"
        }
    }

    private static func invalidRenderedFragment(in text: String) -> String? {
        for fragment in ["Optional(", "undefined", "NaN"] where text.contains(fragment) {
            return fragment
        }
        return nil
    }
}
