import SwiftLibCore

extension LibraryViewModel {

    // MARK: - Collections

    func saveCollection(_ col: inout Collection) {
        do {
            try db.saveCollection(&col)
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func deleteCollection(id: Int64) {
        do {
            try db.deleteCollection(id: id)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
        if case .collection(let cid) = selectedSidebar, cid == id {
            selectedSidebar = .allReferences
        }
    }

    // MARK: - Tags

    func saveTag(_ tag: inout Tag) {
        do {
            try db.saveTag(&tag)
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func deleteTag(id: Int64) {
        do {
            try db.deleteTag(id: id)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}
