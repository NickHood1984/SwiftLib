import Foundation
import SwiftLibCore

/// Parses CNKI's structured export text format into Reference objects.
///
/// CNKI export text uses a key-value format with `{key}` prefixes:
/// ```
/// {Reference Type}: Journal Article
/// {Title}: 深度学习在自然语言处理中的应用
/// {Author}: 张三;李四
/// {Source}: 计算机学报
/// {Year}: 2023
/// {Volume}: 45
/// {Issue}: 3
/// {Pages}: 100-112
/// {DOI}: 10.xxxx/xxxxx
/// {Abstract}: ...
/// {Keywords}: 深度学习;自然语言处理;神经网络
/// ```
enum CNKIExportParser {

    /// Parse a CNKI export text block (potentially containing multiple records).
    static func parse(_ text: String) -> [Reference] {
        let records = splitRecords(text)
        return records.compactMap { parseRecord($0) }
    }

    /// Split multi-record export text into individual record strings.
    private static func splitRecords(_ text: String) -> [String] {
        // Records are typically separated by blank lines or "{Reference Type}"
        let lines = text.components(separatedBy: .newlines)
        var records: [String] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty && !current.isEmpty {
                records.append(current.joined(separator: "\n"))
                current = []
            } else if !trimmed.isEmpty {
                current.append(line)
            }
        }
        if !current.isEmpty {
            records.append(current.joined(separator: "\n"))
        }

        return records
    }

    /// Parse a single CNKI export record into a Reference.
    private static func parseRecord(_ record: String) -> Reference? {
        var fields: [String: String] = [:]
        var currentKey: String?
        var currentValue: [String] = []

        for line in record.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match {Key}: Value pattern
            if let match = trimmed.range(of: #"^\{(.+?)\}\s*[:：]\s*(.*)$"#, options: .regularExpression) {
                // Save previous field
                if let key = currentKey {
                    fields[key] = currentValue.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let fullMatch = String(trimmed[match])
                let components = fullMatch.split(separator: ":", maxSplits: 1).count > 1
                    ? fullMatch.split(separator: ":", maxSplits: 1)
                    : fullMatch.split(separator: "：", maxSplits: 1)
                if components.count == 2 {
                    currentKey = String(components[0])
                        .replacingOccurrences(of: "{", with: "")
                        .replacingOccurrences(of: "}", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    currentValue = [String(components[1]).trimmingCharacters(in: .whitespaces)]
                }
            } else if !trimmed.isEmpty, currentKey != nil {
                // Continuation line
                currentValue.append(trimmed)
            }
        }
        // Save last field
        if let key = currentKey {
            fields[key] = currentValue.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Must have at least a title
        guard let title = (fields["Title"] ?? fields["题名"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }

        // Parse authors (semicolon-separated)
        let authorNames: [AuthorName] = {
            let raw = fields["Author"] ?? fields["作者"] ?? ""
            return raw.split(separator: ";").compactMap { part -> AuthorName? in
                let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return AuthorName(given: "", family: name)
            }
        }()

        // Parse year
        let year: Int? = {
            if let y = fields["Year"] ?? fields["年"] {
                return Int(y.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }()

        // Parse reference type
        let referenceType: ReferenceType = {
            let typeStr = (fields["Reference Type"] ?? fields["文献类型"] ?? "").lowercased()
            if typeStr.contains("journal") || typeStr.contains("期刊") { return .journalArticle }
            if typeStr.contains("thesis") || typeStr.contains("学位") { return .thesis }
            if typeStr.contains("conference") || typeStr.contains("会议") { return .conferencePaper }
            if typeStr.contains("book") || typeStr.contains("图书") { return .book }
            if typeStr.contains("report") || typeStr.contains("报告") { return .report }
            return .journalArticle // default for CNKI
        }()

        var ref = Reference(
            title: title,
            authors: authorNames,
            year: year,
            journal: fields["Source"] ?? fields["来源"],
            volume: fields["Volume"] ?? fields["卷"],
            issue: fields["Issue"] ?? fields["期"],
            pages: fields["Pages"] ?? fields["页码"],
            doi: fields["DOI"],
            abstract: fields["Abstract"] ?? fields["摘要"],
            referenceType: referenceType,
            metadataSource: .cnki
        )

        ref.keywords = {
            let raw = fields["Keywords"] ?? fields["关键词"] ?? ""
            let list = raw.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !list.isEmpty else { return nil }
            return (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) }
        }()

        ref.institution = fields["Institution"] ?? fields["机构"]
        ref.issn = fields["ISSN"]
        ref.language = "zh-CN"

        return ref
    }
}
