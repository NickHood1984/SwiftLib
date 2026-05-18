import Foundation
import Combine
import GRDB

// MARK: - PDF Annotation CRUD
extension AppDatabase {
    public func saveAnnotation(_ annotation: inout PDFAnnotationRecord) throws {
        try dbWriter.write { db in
            try annotation.save(db)
        }
    }

    public func saveAnnotations(_ annotations: inout [PDFAnnotationRecord]) throws {
        guard !annotations.isEmpty else { return }
        try dbWriter.write { db in
            for index in annotations.indices {
                try annotations[index].save(db)
            }
        }
    }

    public func deleteAnnotation(id: Int64) throws {
        try dbWriter.write { db in
            _ = try PDFAnnotationRecord.deleteOne(db, id: id)
        }
    }

    public func fetchAnnotations(referenceId: Int64) throws -> [PDFAnnotationRecord] {
        try dbWriter.read { db in
            try PDFAnnotationRecord
                .filter(PDFAnnotationRecord.Columns.referenceId == referenceId)
                .order(PDFAnnotationRecord.Columns.pageIndex)
                .order(PDFAnnotationRecord.Columns.dateCreated)
                .fetchAll(db)
        }
    }

    public func observeAnnotations(referenceId: Int64) -> AnyPublisher<[PDFAnnotationRecord], Error> {
        ValueObservation
            .tracking { db in
                try PDFAnnotationRecord
                    .filter(PDFAnnotationRecord.Columns.referenceId == referenceId)
                    .order(PDFAnnotationRecord.Columns.pageIndex)
                    .order(PDFAnnotationRecord.Columns.dateCreated)
                    .fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    public func annotationCount(referenceId: Int64) throws -> Int {
        try dbWriter.read { db in
            try PDFAnnotationRecord
                .filter(PDFAnnotationRecord.Columns.referenceId == referenceId)
                .fetchCount(db)
        }
    }
}


// MARK: - Web Annotation CRUD
extension AppDatabase {
    public func saveWebAnnotation(_ annotation: inout WebAnnotationRecord) throws {
        try dbWriter.write { db in
            try annotation.save(db)
        }
    }

    public func deleteWebAnnotation(id: Int64) throws {
        try dbWriter.write { db in
            _ = try WebAnnotationRecord.deleteOne(db, id: id)
        }
    }

    public func fetchWebAnnotations(referenceId: Int64) throws -> [WebAnnotationRecord] {
        try dbWriter.read { db in
            try WebAnnotationRecord
                .filter(WebAnnotationRecord.Columns.referenceId == referenceId)
                .order(WebAnnotationRecord.Columns.dateCreated)
                .fetchAll(db)
        }
    }

    public func observeWebAnnotations(referenceId: Int64) -> AnyPublisher<[WebAnnotationRecord], Error> {
        ValueObservation
            .tracking { db in
                try WebAnnotationRecord
                    .filter(WebAnnotationRecord.Columns.referenceId == referenceId)
                    .order(WebAnnotationRecord.Columns.dateCreated)
                    .fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    public func webAnnotationCount(referenceId: Int64) throws -> Int {
        try dbWriter.read { db in
            try WebAnnotationRecord
                .filter(WebAnnotationRecord.Columns.referenceId == referenceId)
                .fetchCount(db)
        }
    }
}
