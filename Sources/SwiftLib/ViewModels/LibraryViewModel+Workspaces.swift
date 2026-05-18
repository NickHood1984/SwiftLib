import SwiftLibCore

extension LibraryViewModel {

    var selectedWorkspace: Workspace? {
        guard let selectedWorkspaceID else { return nil }
        return workspaces.first { $0.id == selectedWorkspaceID }
    }

    func selectWorkspace(id: Int64) {
        selectedWorkspaceID = id
    }

    func saveWorkspace(_ workspace: inout Workspace) {
        do {
            try db.saveWorkspace(&workspace)
        } catch {
            errorMessage = "Workspace save failed: \(error.localizedDescription)"
        }
    }

    func deleteWorkspace(id: Int64) {
        do {
            try db.deleteWorkspace(id: id)
        } catch {
            errorMessage = "Workspace delete failed: \(error.localizedDescription)"
        }

        if selectedWorkspaceID == id {
            selectedWorkspaceID = workspaces.first(where: { $0.kind == .all })?.id
        }
    }

    func saveWorkspaceLayoutSnapshot(_ snapshot: WorkspaceLayoutSnapshot, workspaceId: Int64) {
        do {
            try db.saveWorkspaceLayoutSnapshot(snapshot, forWorkspaceId: workspaceId)
        } catch {
            errorMessage = "Layout snapshot save failed: \(error.localizedDescription)"
        }
    }

    func addReferences(ids: Set<Int64>, toWorkspaceId workspaceId: Int64) {
        do {
            try db.addReferences(ids: Array(ids), toWorkspaceId: workspaceId)
        } catch {
            errorMessage = "Add to workspace failed: \(error.localizedDescription)"
        }
    }

    func removeReferences(ids: Set<Int64>, fromWorkspaceId workspaceId: Int64) {
        do {
            try db.removeReferences(ids: Array(ids), fromWorkspaceId: workspaceId)
        } catch {
            errorMessage = "Remove from workspace failed: \(error.localizedDescription)"
        }
    }
}
