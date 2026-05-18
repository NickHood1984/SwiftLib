import Foundation
import Combine
import GRDB

// MARK: - Collection CRUD
extension AppDatabase {
    public func saveCollection(_ collection: inout Collection) throws {
        try dbWriter.write { db in
            try collection.save(db)
        }
    }

    public func deleteCollection(id: Int64) throws {
        try dbWriter.write { db in
            _ = try Collection.deleteOne(db, id: id)
        }
    }

    public func fetchAllCollections() throws -> [Collection] {
        try dbWriter.read { db in
            try Collection.order(Collection.Columns.name).fetchAll(db)
        }
    }

    public func observeCollections() -> AnyPublisher<[Collection], Error> {
        ValueObservation
            .tracking { db in
                try Collection.order(Collection.Columns.name).fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}
