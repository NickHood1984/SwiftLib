import Foundation

enum StructuredJSONCandidateState: Equatable {
    case none
    case incomplete
    case complete(String)
}

enum StructuredJSONCandidateExtractor {
    static func completeCandidates(
        in response: String,
        requireStructuredPrefix: Bool = false
    ) -> [String] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let scannable = stripLeadingCodeFence(from: trimmed)
        if requireStructuredPrefix, !startsWithStructuredPayload(scannable) {
            return []
        }

        var candidates: [String] = []
        var stack: [Character] = []
        var inString = false
        var isEscaping = false
        var startIndex: String.Index?

        for index in scannable.indices {
            let character = scannable[index]

            if inString {
                if isEscaping {
                    isEscaping = false
                    continue
                }
                if character == "\\" {
                    isEscaping = true
                    continue
                }
                if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{", "[":
                if stack.isEmpty {
                    startIndex = index
                }
                stack.append(character == "{" ? "}" : "]")
            case "}", "]":
                guard let expected = stack.last, expected == character else {
                    stack.removeAll(keepingCapacity: true)
                    startIndex = nil
                    continue
                }
                stack.removeLast()
                if stack.isEmpty, let candidateStartIndex = startIndex {
                    candidates.append(String(scannable[candidateStartIndex...index]))
                    startIndex = nil
                }
            default:
                break
            }
        }

        return candidates
    }

    static func candidateState(
        in response: String,
        requireStructuredPrefix: Bool = false
    ) -> StructuredJSONCandidateState {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        let scannable = stripLeadingCodeFence(from: trimmed)
        if requireStructuredPrefix, !startsWithStructuredPayload(scannable) {
            return .none
        }

        guard let startIndex = firstStructuredStartIndex(in: scannable) else {
            return .none
        }

        var stack: [Character] = []
        var inString = false
        var isEscaping = false
        var endIndex: String.Index?

        for index in scannable[startIndex...].indices {
            let character = scannable[index]

            if inString {
                if isEscaping {
                    isEscaping = false
                    continue
                }
                if character == "\\" {
                    isEscaping = true
                    continue
                }
                if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                stack.append("}")
            case "[":
                stack.append("]")
            case "}", "]":
                guard let expected = stack.last, expected == character else {
                    return .incomplete
                }
                stack.removeLast()
                if stack.isEmpty {
                    endIndex = index
                    break
                }
            default:
                break
            }

            if endIndex != nil {
                break
            }
        }

        guard !inString, !isEscaping, stack.isEmpty, let endIndex else {
            return .incomplete
        }

        return .complete(String(scannable[startIndex...endIndex]))
    }

    private static func stripLeadingCodeFence(from text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        guard let newlineIndex = text.firstIndex(of: "\n") else { return text }
        let nextIndex = text.index(after: newlineIndex)
        return String(text[nextIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func startsWithStructuredPayload(_ text: String) -> Bool {
        guard let first = text.first(where: { !$0.isWhitespace }) else { return false }
        return first == "{" || first == "["
    }

    private static func firstStructuredStartIndex(in text: String) -> String.Index? {
        let firstBrace = text.firstIndex(of: "{")
        let firstBracket = text.firstIndex(of: "[")

        switch (firstBrace, firstBracket) {
        case let (brace?, bracket?):
            return min(brace, bracket)
        case let (brace?, nil):
            return brace
        case let (nil, bracket?):
            return bracket
        default:
            return nil
        }
    }
}
