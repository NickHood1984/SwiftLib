import Foundation
import GRDB
import os.log

private let appDatabaseLog = Logger(subsystem: "SwiftLib", category: "AppDatabase")

// MARK: - Database Access
extension AppDatabase {
    public enum SharedStorageMode: Sendable {
        case persistent
        case inMemoryFallback
    }

    private struct SharedBootstrap {
        let database: AppDatabase
        let storageMode: SharedStorageMode
        let startupErrorDescription: String?
    }

    private static let sharedBootstrap = makeSharedBootstrap()

    /// Compatibility accessor for callers that only need a usable shared database.
    public static let sharedResult: Result<AppDatabase, Error> = .success(sharedBootstrap.database)

    public static var shared: AppDatabase { sharedBootstrap.database }

    public static var sharedStorageMode: SharedStorageMode { sharedBootstrap.storageMode }

    public static var sharedStartupErrorDescription: String? {
        sharedBootstrap.startupErrorDescription
    }

    private static func preferredStorageRoot(named leaf: String) -> URL {
        let fm = FileManager.default
        let candidates: [URL] = [
            (try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )),
            fm.temporaryDirectory.appendingPathComponent("SwiftLibFallback", isDirectory: true),
        ].compactMap { $0 }

        for base in candidates {
            let dirURL = base.appendingPathComponent(leaf, isDirectory: true)
            do {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                return dirURL
            } catch {
                appDatabaseLog.error("Failed to create directory at \(dirURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return fm.temporaryDirectory.appendingPathComponent(leaf, isDirectory: true)
    }

    private static func makeSharedBootstrap() -> SharedBootstrap {
        let dirURL = preferredStorageRoot(named: "SwiftLib")
        do {
            let dbURL = dirURL.appendingPathComponent("library.sqlite")
            var config = Configuration()
            #if DEBUG
            if SwiftLibCoreDebugLogging.sqlTrace {
                config.prepareDatabase { db in
                    db.trace { print("SQL: \($0)") }
                }
            }
            #endif
            let dbPool = try DatabasePool(path: dbURL.path, configuration: config)

            return SharedBootstrap(
                database: try AppDatabase(dbPool),
                storageMode: .persistent,
                startupErrorDescription: nil
            )
        } catch {
            appDatabaseLog.error("Primary database setup failed at \(dirURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")

            do {
                return SharedBootstrap(
                    database: try AppDatabase(DatabaseQueue(path: ":memory:")),
                    storageMode: .inMemoryFallback,
                    startupErrorDescription: error.localizedDescription
                )
            } catch {
                preconditionFailure("Unable to initialize in-memory database fallback: \(error.localizedDescription)")
            }
        }
    }

    /// PDF storage directory
    public static var pdfStorageURL: URL {
        preferredStorageRoot(named: "SwiftLib/PDFs")
    }

    public static var metadataArtifactsURL: URL {
        preferredStorageRoot(named: "SwiftLib/MetadataArtifacts")
    }
}
