import XCTest
import GRDB
@testable import SwiftLib
@testable import SwiftLibCore

@MainActor
final class LibraryViewModelTests: XCTestCase {

    private func makeTestDB() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(path: ":memory:"))
    }

    // MARK: - Initialization

    func testViewModelInitialState() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        XCTAssertEqual(vm.searchText, "")
        XCTAssertFalse(vm.isImporting)
        XCTAssertNil(vm.importProgress)
        XCTAssertNil(vm.errorMessage)
    }

    func testDefaultSidebarSelection() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        XCTAssertEqual(vm.selectedSidebar, .allReferences)
    }

    func testComputeTitleKeywordsUsesDistinctTitlesAndFiltersStopWords() {
        let keywords = LibraryViewModel.computeTitleKeywords(
            from: [
                "Deep Learning for Vision",
                "Deep Learning in Medicine",
                "The Vision of Learning Systems",
                "learning learning learning",
                "的 研究 分析"
            ]
        )

        XCTAssertEqual(keywords.first?.word, "learning")
        XCTAssertEqual(keywords.first?.count, 4)
        XCTAssertEqual(keywords.first(where: { $0.word == "vision" })?.count, 2)
        XCTAssertFalse(keywords.contains(where: { $0.word == "the" }))
        XCTAssertFalse(keywords.contains(where: { $0.word == "研究" }))
    }

    func testLoadMoreIfNeededDoesNotAppendDuplicatePages() async throws {
        let db = try makeTestDB()

        for index in 0..<220 {
            var ref = Reference(title: "Reference \(index)")
            try db.saveReference(&ref)
        }

        let vm = LibraryViewModel(db: db)
        try await waitUntil(timeout: 2) { vm.references.count == 200 }

        guard let lastVisible = vm.references.last else {
            return XCTFail("Expected the initial page to be populated")
        }

        vm.loadMoreIfNeeded(currentItem: lastVisible)
        vm.loadMoreIfNeeded(currentItem: lastVisible)

        try await waitUntil(timeout: 2) { vm.references.count == 220 }
        XCTAssertEqual(vm.references.count, 220)
        XCTAssertEqual(Set(vm.references.compactMap(\.id)).count, 220)
    }

    // MARK: - Save Reference

    func testSaveReference() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        var ref = Reference(title: "ViewModel Save Test")
        vm.saveReference(&ref)
        XCTAssertNotNil(ref.id, "Saved reference should have an ID")
        XCTAssertNil(vm.errorMessage, "No error should occur")
    }

    func testSaveReferenceSetsDateModified() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        var ref = Reference(title: "Date Modified Test")
        let before = Date()
        vm.saveReference(&ref)
        XCTAssertGreaterThanOrEqual(ref.dateModified, before)
    }

    // MARK: - Delete Reference

    func testDeleteReferenceRemovesFromDB() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        var ref = Reference(title: "Delete DB Test")
        vm.saveReference(&ref)
        let id = ref.id!

        vm.deleteReferences(ids: Set([id]))
        let fetched = try db.fetchReferences(ids: [id])
        XCTAssertTrue(fetched.isEmpty, "Deleted reference should not be fetchable")
    }

    // MARK: - Collection Management

    func testSaveCollection() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        var col = Collection(name: "ViewModel Col Test")
        vm.saveCollection(&col)
        XCTAssertNotNil(col.id)
        XCTAssertNil(vm.errorMessage)
    }

    func testDeleteCollectionResetsSidebar() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        var col = Collection(name: "Delete Col Test")
        vm.saveCollection(&col)
        let colId = col.id!

        vm.selectedSidebar = .collection(colId)
        vm.deleteCollection(id: colId)
        XCTAssertEqual(vm.selectedSidebar, .allReferences,
                       "Sidebar should reset to allReferences after deleting the selected collection")
    }

    func testDeleteCollectionDoesNotResetSidebarIfDifferent() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        var col1 = Collection(name: "Col 1")
        var col2 = Collection(name: "Col 2")
        vm.saveCollection(&col1)
        vm.saveCollection(&col2)

        vm.selectedSidebar = .collection(col1.id!)
        vm.deleteCollection(id: col2.id!)
        XCTAssertEqual(vm.selectedSidebar, .collection(col1.id!),
                       "Sidebar should not change when deleting a different collection")
    }

    // MARK: - Tag Management

    func testSaveTag() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        var tag = Tag(name: "ViewModel Tag Test", color: "#FF0000")
        vm.saveTag(&tag)
        XCTAssertNotNil(tag.id)
        XCTAssertNil(vm.errorMessage)
    }

    func testDeleteTag() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        var tag = Tag(name: "Delete Tag Test")
        vm.saveTag(&tag)
        let id = tag.id!

        vm.deleteTag(id: id)
        let all = try db.fetchAllTags()
        XCTAssertFalse(all.contains(where: { $0.id == id }))
    }

    // MARK: - Error Handling

    func testErrorMessageClearsOnNil() throws {
        let db = try makeTestDB()
        let vm = LibraryViewModel(db: db)
        vm.errorMessage = "Test error"
        XCTAssertEqual(vm.errorMessage, "Test error")
        vm.errorMessage = nil
        XCTAssertNil(vm.errorMessage)
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}
