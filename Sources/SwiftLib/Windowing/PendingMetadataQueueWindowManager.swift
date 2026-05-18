import SwiftUI
import Combine
import SwiftLibCore

struct PendingQueueWindowID: Codable, Hashable {
    let id: String
    static let value = PendingQueueWindowID(id: "main")
}

@MainActor
final class PendingMetadataQueueWindowManager {
    static let shared = PendingMetadataQueueWindowManager()

    private(set) var intakesPublisher: AnyPublisher<[MetadataIntake], Never>?
    private(set) var resolver: MetadataResolver?
    private(set) var onPersistResult: ((MetadataResolutionResult, MetadataIntake) -> Void)?
    private(set) var onConfirmManual: ((MetadataIntake) -> Void)?
    private(set) var onDelete: ((MetadataIntake) -> Void)?

    private init() {}

    func clear() {
        intakesPublisher = nil
        resolver = nil
        onPersistResult = nil
        onConfirmManual = nil
        onDelete = nil
    }

    func configure(
        intakesPublisher: AnyPublisher<[MetadataIntake], Never>,
        resolver: MetadataResolver,
        onPersistResult: @escaping (MetadataResolutionResult, MetadataIntake) -> Void,
        onConfirmManual: @escaping (MetadataIntake) -> Void,
        onDelete: @escaping (MetadataIntake) -> Void
    ) {
        self.intakesPublisher = intakesPublisher
        self.resolver = resolver
        self.onPersistResult = onPersistResult
        self.onConfirmManual = onConfirmManual
        self.onDelete = onDelete
    }
}
