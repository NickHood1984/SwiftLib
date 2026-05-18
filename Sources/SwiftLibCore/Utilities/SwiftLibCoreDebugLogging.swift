import Foundation

enum SwiftLibCoreDebugLogging {
    private static let environment = ProcessInfo.processInfo.environment

    static let runtimeVerbose =
        environment["SWIFTLIB_DEBUG_METADATA"] == "1"
        || environment["SWIFTLIB_DEBUG_RUNTIME"] == "1"

    static let sqlTrace =
        runtimeVerbose
        || environment["SWIFTLIB_DEBUG_SQL"] == "1"
}
