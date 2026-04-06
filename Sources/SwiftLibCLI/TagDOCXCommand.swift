import ArgumentParser
import Foundation
import SwiftLibCore

struct TagDOCX: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag-docx",
        abstract: "Wrap existing superscript numeric citations in a .docx with SwiftLib citation tags"
    )

    @Argument(help: "Path to the .docx file")
    var file: String

    @Option(name: .long, help: "Output path for the tagged .docx copy")
    var output: String?

    @Option(name: .shortAndLong, help: "Citation style stored in the tag metadata")
    var style: String = "nature"

    @Option(name: .long, help: "Restrict citation matching to references in the given collection ID")
    var collection: Int64?

    @Flag(name: .long, help: "Overwrite the input .docx in place")
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
