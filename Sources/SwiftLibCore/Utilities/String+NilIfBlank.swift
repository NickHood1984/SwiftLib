import Foundation

public extension String {
    var swiftlib_nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public extension Optional where Wrapped == String {
    var swiftlib_nilIfBlank: String? {
        switch self {
        case .none:
            return nil
        case .some(let value):
            return value.swiftlib_nilIfBlank
        }
    }
}
