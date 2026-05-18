import SwiftLibCore

extension LibraryViewModel {

    func persistMetadataResolution(
        _ result: MetadataResolutionResult,
        options: MetadataPersistenceOptions
    ) -> MetadataPersistenceResult? {
        do {
            return try db.persistMetadataResolution(result, options: options)
        } catch {
            errorMessage = "Metadata persistence failed: \(error.localizedDescription)"
            return nil
        }
    }

    func confirmPendingMetadataIntake(_ intake: MetadataIntake, reviewedBy: String = "manual-queue") -> Reference? {
        do {
            return try db.confirmMetadataIntake(intake, reviewedBy: reviewedBy)
        } catch {
            errorMessage = "Manual verification failed: \(error.localizedDescription)"
            return nil
        }
    }

    func deletePendingMetadataIntake(_ intake: MetadataIntake) {
        guard let id = intake.id else { return }
        do {
            try db.deleteMetadataIntake(id: id)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}
