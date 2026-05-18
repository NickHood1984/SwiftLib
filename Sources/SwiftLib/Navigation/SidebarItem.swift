import SwiftUI
import SwiftLibCore

enum SidebarItem: Hashable {
    case allReferences
    case collection(Int64)
    case tag(Int64)
    case titleKeyword(String)
}

extension SidebarItem {
    init(snapshotSelection: WorkspaceSidebarSelection) {
        switch snapshotSelection {
        case .allReferences:
            self = .allReferences
        case .collection(let id):
            self = .collection(id)
        case .tag(let id):
            self = .tag(id)
        case .titleKeyword(let word):
            self = .titleKeyword(word)
        }
    }

    var snapshotSelection: WorkspaceSidebarSelection {
        switch self {
        case .allReferences:
            return .allReferences
        case .collection(let id):
            return .collection(id)
        case .tag(let id):
            return .tag(id)
        case .titleKeyword(let word):
            return .titleKeyword(word)
        }
    }
}

extension WorkspaceColumnVisibility {
    init(_ visibility: NavigationSplitViewVisibility) {
        switch visibility {
        case .automatic:
            self = .automatic
        case .all:
            self = .all
        case .doubleColumn:
            self = .doubleColumn
        case .detailOnly:
            self = .detailOnly
        default:
            self = .all
        }
    }

    var navigationSplitViewVisibility: NavigationSplitViewVisibility {
        switch self {
        case .automatic:
            return .automatic
        case .all:
            return .all
        case .doubleColumn:
            return .doubleColumn
        case .detailOnly:
            return .detailOnly
        }
    }
}
