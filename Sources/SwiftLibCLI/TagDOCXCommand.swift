import ArgumentParser
import Foundation
import SwiftLibCore

struct TagDOCX: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag-docx",
        abstract: "将 .docx 中已有的上标数字引用替换为 SwiftLib 引用标签"
    )

    @Argument(help: ".docx 文件路径")
    var file: String

    @Option(name: .long, help: "标记后输出的 .docx 路径")
    var output: String?

    @Option(name: .shortAndLong, help: "存储在标签元数据中的引用样式")
    var style: String = "nature"

    @Option(name: .long, help: "仅匹配指定分组 ID 内的文献")
    var collection: Int64?

    @Flag(name: .long, help: "直接覆盖原文件")
    var inPlace = false

    func run() throws {
        let inputURL = URL(fileURLWithPath: file)
        guard inputURL.pathExtension.lowercased() == "docx" else {
            printJSONError("Only .docx files are supported")
            throw ExitCode.failure
        }

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
                .appendingPathComponent("\(stem).swiftlib-tagged.docx")
        }

        let references: [Reference]
        if let collection {
            references = try AppDatabase.shared.fetchReferences(collectionId: collection)
        } else {
            references = try AppDatabase.shared.fetchAllReferences(limit: 0)
        }
        let report = try WordCitationMarker.markDOCX(
            at: inputURL,
            outputURL: outputURL,
            references: references,
            style: style
        )
        printJSON(report)
    }
}
