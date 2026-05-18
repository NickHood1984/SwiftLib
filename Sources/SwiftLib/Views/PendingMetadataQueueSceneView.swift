import SwiftUI
import SwiftLibCore

struct PendingMetadataQueueSceneView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let manager = PendingMetadataQueueWindowManager.shared
        if let publisher = manager.intakesPublisher,
           let resolver = manager.resolver,
           let onPersist = manager.onPersistResult,
           let onConfirm = manager.onConfirmManual,
           let onDelete = manager.onDelete {
            PendingMetadataQueueView(
                intakesPublisher: publisher,
                resolver: resolver,
                onPersistResult: onPersist,
                onConfirmManual: onConfirm,
                onDelete: onDelete
            )
            .onDisappear {
                manager.clear()
            }
        } else {
            Color.clear
                .frame(width: 720, height: 520)
                .onAppear {
                    dismissWindow()
                }
        }
    }
}
