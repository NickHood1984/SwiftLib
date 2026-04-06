import Foundation

extension Notification.Name {
    static let swiftLibClipImported = Notification.Name("SwiftLibClipImported")
}

enum SwiftLibClipImportedKeys {
    static let id = "id"
    static let title = "title"
}
