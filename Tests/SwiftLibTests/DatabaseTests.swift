import Foundation
import GRDB
import XCTest
@testable import SwiftLib
@testable import SwiftLibCore

final class DatabaseTests: XCTestCase {
    func testSaveFetchAndSearchReferencesPreserveStructuredAuthors() throws {
        let db = try makeDatabase()
        var older = Reference(
            title: "Earlier entry",
            authors: [AuthorName(given: "Jane", family: "Doe")],
            dateAdded: Date(timeIntervalSince1970: 10),
            dateModified: Date(timeIntervalSince1970: 10)
        )
        var newer = Reference(
            title: "Machine Learning Systems",
            authors: [AuthorName(given: "John", family: "Smith")],
            dateAdded: Date(timeIntervalSince1970: 20),
            dateModified: Date(timeIntervalSince1970: 20),
            notes: "Prefix searching should find this entry"
        )

        try db.saveReference(&older)
        try db.saveReference(&newer)

        let fetched = try db.fetchAllReferences()
        let limited = try db.fetchAllReferences(limit: 1)
        let matches = try db.searchReferences(query: "Machine")

        XCTAssertEqual(fetched.map(\.title), ["Machine Learning Systems", "Earlier entry"])
        XCTAssertEqual(limited.map(\.title), ["Machine Learning Systems"])
        XCTAssertEqual(matches.map(\.title), ["Machine Learning Systems"])
        XCTAssertEqual(matches.first?.authors, [AuthorName(given: "John", family: "Smith")])
    }

    func testCollectionsBatchImportAndCollectionCountsWorkTogether() throws {
        let db = try makeDatabase()
        var collection = Collection(name: "Reading List")
        try db.saveCollection(&collection)

        let imported = try db.batchImportReferences([
            Reference(title: "One", collectionId: collection.id),
            Reference(title: "Two", collectionId: collection.id),
            Reference(title: "Three"),
        ])

        XCTAssertEqual(imported, 3)
        XCTAssertEqual(try db.referenceCount(), 3)
        XCTAssertEqual(try db.referenceCount(collectionId: try XCTUnwrap(collection.id)), 2)
        XCTAssertEqual(try db.fetchAllCollections().map(\.name), ["Reading List"])
    }

    func testUpdateReferenceWebContentReplacesStoredBody() throws {
        let db = try makeDatabase()
        var reference = Reference(
            title: "YouTube entry",
            webContent: Reference.encodeWebContent("<article></article>", format: .html)
        )
        try db.saveReference(&reference)

        let referenceID = try XCTUnwrap(reference.id)
        let updatedBody = "<article><details class=\"swiftlib-yt-transcript\" open><summary>字幕 / Transcript</summary><pre>line</pre></details></article>"
        try db.updateReferenceWebContent(
            id: referenceID,
            webContent: Reference.encodeWebContent(updatedBody, format: .html)
        )

        let fetched = try db.fetchReferences(ids: [referenceID])
        XCTAssertEqual(fetched.first?.decodedWebContent?.body, updatedBody)
    }

    func testSetTagsForReferenceReplacesExistingAssignments() throws {
        let db = try makeDatabase()
        var reference = Reference(title: "Tagged reference")
        try db.saveReference(&reference)

        var firstTag = Tag(name: "Swift")
        var secondTag = Tag(name: "Testing")
        try db.saveTag(&firstTag)
        try db.saveTag(&secondTag)

        let referenceID = try XCTUnwrap(reference.id)
        try db.setTags(
            forReference: referenceID,
            tagIds: [try XCTUnwrap(firstTag.id), try XCTUnwrap(secondTag.id)]
        )
        XCTAssertEqual(
            try db.fetchTags(forReference: referenceID).map(\.name).sorted(),
            ["Swift", "Testing"]
        )

        try db.setTags(forReference: referenceID, tagIds: [try XCTUnwrap(secondTag.id)])
        XCTAssertEqual(try db.fetchTags(forReference: referenceID).map(\.name), ["Testing"])
        XCTAssertEqual(
            try db.fetchReferences(tagId: try XCTUnwrap(secondTag.id)).map(\.title),
            ["Tagged reference"]
        )
    }

    func testPDFAndWebAnnotationCRUDUseReferenceForeignKeys() throws {
        let db = try makeDatabase()
        var reference = Reference(title: "Annotated reference")
        try db.saveReference(&reference)
        let referenceID = try XCTUnwrap(reference.id)

        var pdfAnnotation = PDFAnnotationRecord(
            referenceId: referenceID,
            type: .highlight,
            selectedText: "Important",
            pageIndex: 2,
            rects: [CGRect(x: 10, y: 10, width: 20, height: 5)]
        )
        var webAnnotation = WebAnnotationRecord(
            referenceId: referenceID,
            type: .note,
            selectedText: "Selected",
            noteText: "Remember this",
            anchorText: "Selected"
        )

        try db.saveAnnotation(&pdfAnnotation)
        try db.saveWebAnnotation(&webAnnotation)

        XCTAssertEqual(try db.annotationCount(referenceId: referenceID), 1)
        XCTAssertEqual(try db.webAnnotationCount(referenceId: referenceID), 1)
        XCTAssertEqual(try db.fetchAnnotations(referenceId: referenceID).first?.selectedText, "Important")
        XCTAssertEqual(try db.fetchWebAnnotations(referenceId: referenceID).first?.noteText, "Remember this")

        try db.deleteAnnotation(id: try XCTUnwrap(pdfAnnotation.id))
        try db.deleteWebAnnotation(id: try XCTUnwrap(webAnnotation.id))

        XCTAssertEqual(try db.annotationCount(referenceId: referenceID), 0)
        XCTAssertEqual(try db.webAnnotationCount(referenceId: referenceID), 0)
    }

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(path: ":memory:"))
    }
}
