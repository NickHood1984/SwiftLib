import Foundation
import Combine
import GRDB

// MARK: - Tag CRUD
extension AppDatabase {
    public func saveTag(_ tag: inout Tag) throws {
        try dbWriter.write { db in
            try tag.save(db)
        }
    }

    public func deleteTag(id: Int64) throws {
        try dbWriter.write { db in
            _ = try Tag.deleteOne(db, id: id)
        }
    }

    public func fetchAllTags() throws -> [Tag] {
        try dbWriter.read { db in
            try Tag.order(Tag.Columns.name).fetchAll(db)
        }
    }

    public func fetchTags(forReference refId: Int64) throws -> [Tag] {
        try dbWriter.read { db in
            let request = Tag
                .joining(required: Tag.referenceTagPivot
                    .filter(ReferenceTag.Columns.referenceId == refId))
            return try request.fetchAll(db)
        }
    }

    public func setTags(forReference refId: Int64, tagIds: [Int64]) throws {
        try dbWriter.write { db in
            try ReferenceTag.filter(ReferenceTag.Columns.referenceId == refId).deleteAll(db)
            for tagId in tagIds {
                let pivot = ReferenceTag(referenceId: refId, tagId: tagId)
                try pivot.insert(db)
            }
        }
    }

    public func observeTags() -> AnyPublisher<[Tag], Error> {
        ValueObservation
            .tracking { db in
                try Tag.order(Tag.Columns.name).fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}
