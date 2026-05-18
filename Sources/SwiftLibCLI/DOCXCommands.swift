import ArgumentParser
import Foundation
import SwiftLibCore

struct RefreshDOCX: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refresh-docx",
        abstract: "刷新 .docx 中的 SwiftLib 引文编号和参考文献表"
    )

    @Argument(help: ".docx 文件路径")
    var file: String

    @Option(name: .long, help: "刷新后的 .docx 输出路径")
    var output: String?

    @Option(name: .shortAndLong, help: "未能从文档标签读取样式时使用的默认样式")
    var style: String = "nature"

    @Option(name: .long, help: "仅使用指定分组 ID 内的文献")
    var collection: Int64?

    @Flag(name: .long, help: "直接覆盖原文件")
    var inPlace = false

    func run() throws {
        let inputURL = try validateDOCXPath(file)
        if inPlace, output != nil {
            printJSONError("Use either --in-place or --output, not both")
            throw ExitCode.failure
        }

        let outputURL: URL
        if inPlace {
            outputURL = inputURL
        } else if let output {
            outputURL = URL(fileURLWithPath: output)
        } else {
            let stem = inputURL.deletingPathExtension().lastPathComponent
            outputURL = inputURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(stem).swiftlib-refreshed.docx")
        }

        let references = try loadReferences(collection: collection)
        let report = try WordCitationDOCXProcessor.refreshDOCX(
            at: inputURL,
            outputURL: outputURL,
            references: references,
            defaultStyle: style
        )
        printJSON(report)
    }
}

struct DocxAudit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docx-audit",
        abstract: "检查 .docx 中 SwiftLib 引文与文献库的一致性"
    )

    @Argument(help: ".docx 文件路径")
    var file: String

    @Option(name: .long, help: "仅使用指定分组 ID 内的文献")
    var collection: Int64?

    func run() throws {
        let inputURL = try validateDOCXPath(file)
        let references = try loadReferences(collection: collection)
        let report = try WordCitationDOCXProcessor.auditDOCX(at: inputURL, references: references)
        printJSON(report)
    }
}

struct PruneUnused: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune-unused",
        abstract: "按 .docx 正文引用裁剪文献库中未使用条目"
    )

    @Option(name: .customLong("from-docx"), help: ".docx 文件路径")
    var docxPath: String

    @Option(name: .long, help: "仅检查指定分组 ID 内的文献")
    var collection: Int64?

    @Flag(name: .long, help: "只输出将被删除的条目，不修改文献库")
    var dryRun = false

    @Flag(name: .long, help: "确认删除未使用条目")
    var force = false

    func run() throws {
        let inputURL = try validateDOCXPath(docxPath)
        let references = try loadReferences(collection: collection)
        let audit = try WordCitationDOCXProcessor.auditDOCX(at: inputURL, references: references)
        let unusedIDs = audit.unusedInLibrary

        if !dryRun && !force {
            printJSONError("Refusing to delete without --dry-run or --force")
            throw ExitCode.failure
        }

        var deletedIDs: [Int64] = []
        if force, !unusedIDs.isEmpty {
            let pdfPaths = try AppDatabase.shared.deleteReferencesReturningPDFPaths(ids: unusedIDs)
            for path in pdfPaths { PDFService.deletePDF(at: path) }
            deletedIDs = unusedIDs
        }

        printJSON(
            PruneUnusedOutput(
                inputPath: inputURL.path,
                dryRun: dryRun,
                scopedLibraryReferenceCount: references.count,
                docUniqueIDCount: audit.docUniqueIDCount,
                unusedInLibrary: unusedIDs,
                deletedIDs: deletedIDs
            )
        )
    }
}

struct PruneUnusedOutput: Encodable {
    let inputPath: String
    let dryRun: Bool
    let scopedLibraryReferenceCount: Int
    let docUniqueIDCount: Int
    let unusedInLibrary: [Int64]
    let deletedIDs: [Int64]
}

private func validateDOCXPath(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    guard url.pathExtension.lowercased() == "docx" else {
        printJSONError("Only .docx files are supported")
        throw ExitCode.failure
    }
    return url
}

private func loadReferences(collection: Int64?) throws -> [Reference] {
    if let collection {
        return try AppDatabase.shared.fetchReferences(collectionId: collection)
    }
    return try AppDatabase.shared.fetchAllReferences(limit: 0)
}
