import SwiftUI
import SwiftLibCore

extension ContentView {

    func currentLayoutSnapshot() -> WorkspaceLayoutSnapshot {
        WorkspaceLayoutSnapshot(
            selectedReferenceId: selectedId,
            sidebarSelection: viewModel.selectedSidebar.snapshotSelection,
            searchText: viewModel.searchText,
            columnVisibility: WorkspaceColumnVisibility(columnVisibility),
            capturedAt: Date()
        )
    }

    func saveCurrentWorkspaceLayoutSnapshot() {
        guard let workspaceId = viewModel.selectedWorkspaceID else { return }
        viewModel.saveWorkspaceLayoutSnapshot(currentLayoutSnapshot(), workspaceId: workspaceId)
    }

    func scheduleWorkspaceLayoutAutosave() {
        guard let workspaceId = viewModel.selectedWorkspaceID else { return }
        let snapshot = currentLayoutSnapshot()

        workspaceLayoutAutosaveTask?.cancel()
        workspaceLayoutAutosaveTask = Task { @MainActor [snapshot, workspaceId] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            viewModel.saveWorkspaceLayoutSnapshot(snapshot, workspaceId: workspaceId)
            workspaceLayoutAutosaveTask = nil
        }
    }

    func switchWorkspace(to workspace: Workspace) {
        guard let workspaceId = workspace.id else { return }
        if viewModel.selectedWorkspaceID != workspaceId {
            saveCurrentWorkspaceLayoutSnapshot()
        }
        viewModel.selectWorkspace(id: workspaceId)
        applyLayoutSnapshot(from: workspace)
        restoredWorkspaceSnapshots.insert(workspaceId)
    }

    func applyLayoutSnapshot(from workspace: Workspace) {
        guard let snapshot = workspace.layoutSnapshot else {
            selectedId = nil
            selectedReference = nil
            viewModel.selectedSidebar = .allReferences
            viewModel.searchText = ""
            columnVisibility = .all
            return
        }

        viewModel.selectedSidebar = validatedSidebarItem(for: snapshot.sidebarSelection)
        viewModel.searchText = snapshot.searchText
        selectedId = snapshot.selectedReferenceId
        columnVisibility = snapshot.columnVisibility.navigationSplitViewVisibility
    }

    func validatedSidebarItem(for snapshotSelection: WorkspaceSidebarSelection) -> SidebarItem {
        let item = SidebarItem(snapshotSelection: snapshotSelection)
        switch item {
        case .collection(let id) where !viewModel.collections.contains(where: { $0.id == id }):
            return .allReferences
        case .tag(let id) where !viewModel.tags.contains(where: { $0.id == id }):
            return .allReferences
        default:
            return item
        }
    }
}
