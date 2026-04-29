import Foundation

// MARK: - easyScholar Journal Rank API

/// Throttled client for easyScholar's open journal-rank endpoint.
/// Rate limit: 2 req/s.  An in-memory LRU cache avoids redundant calls
/// for the same journal name within the same session.
public enum EasyScholarRankProvider {
    public static let endpoint = "https://www.easyscholar.cc/open/getPublicationRank"

    // MARK: - Throttle

    private static let throttle = AsyncThrottle(interval: 0.55) // slightly > 0.5 s for safety

    // MARK: - Cache

    private static var cache: [String: EasyScholarRankResponse] = [:]
    private static let cacheLock = NSLock()

    /// Fetch journal rank for the given publication name.
    /// Returns `nil` if no secretKey is configured or the request fails.
    public static func fetchRank(
        publicationName: String,
        secretKey: String
    ) async -> EasyScholarRankResponse? {
        guard !secretKey.isEmpty else { return nil }
        let normalized = publicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        // Check in-memory cache
        cacheLock.lock()
        if let cached = cache[normalized] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        await throttle.wait()

        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(endpoint)?secretKey=\(secretKey)&publicationName=\(encoded)")
        else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(EasyScholarRankResponse.self, from: data)
            guard decoded.code == 200 else { return nil }

            cacheLock.lock()
            cache[normalized] = decoded
            cacheLock.unlock()
            return decoded
        } catch {
            return nil
        }
    }

    public static func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
}

// MARK: - Response Models

public struct EasyScholarRankResponse: Codable, Hashable, Sendable {
    public let code: Int
    public let msg: String
    public let data: EasyScholarRankData?

    public var isSuccess: Bool { code == 200 }
}

public struct EasyScholarRankData: Codable, Hashable, Sendable {
    public let customRank: EasyScholarCustomRank?
    public let officialRank: EasyScholarOfficialRank?
}

public struct EasyScholarCustomRank: Codable, Hashable, Sendable {
    public let rankInfo: [EasyScholarCustomDataset]?
    public let rank: [String]?
}

public struct EasyScholarCustomDataset: Codable, Hashable, Sendable {
    public let uuid: String
    public let abbName: String
    public let oneRankText: String?
    public let twoRankText: String?
    public let threeRankText: String?
    public let fourRankText: String?
    public let fiveRankText: String?
}

public struct EasyScholarOfficialRank: Codable, Hashable, Sendable {
    public let all: [String: String]?
    public let select: [String: String]?
}

// MARK: - Convenience display helpers

public extension EasyScholarRankData {
    /// Look up a specific rank by its raw abbreviation key (e.g. "sci", "sciup").
    func rank(forKey key: String) -> (label: String, value: String)? {
        let lowercased = key.lowercased()

        // 1. Official — user's selected datasets
        if let value = officialRank?.select?[lowercased], !value.isEmpty {
            return (EasyScholarRankProvider.abbreviationName(for: lowercased), value)
        }
        if let value = officialRank?.all?[lowercased], !value.isEmpty {
            return (EasyScholarRankProvider.abbreviationName(for: lowercased), value)
        }

        // 2. Custom datasets
        if let custom = customRank, let rankInfo = custom.rankInfo, let ranks = custom.rank {
            let infoByUUID = Dictionary(uniqueKeysWithValues: rankInfo.map { ($0.uuid, $0) })
            for rankEntry in ranks {
                let parts = rankEntry.split(separator: "&&&", omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let level = Int(parts[1]),
                      let info = infoByUUID[String(parts[0])] else { continue }
                if info.abbName.lowercased() == lowercased || info.uuid.lowercased() == lowercased {
                    let text: String? = {
                        switch level {
                        case 1: return info.oneRankText
                        case 2: return info.twoRankText
                        case 3: return info.threeRankText
                        case 4: return info.fourRankText
                        case 5: return info.fiveRankText
                        default: return nil
                        }
                    }()
                    if let text, !text.isEmpty {
                        return (info.abbName, text)
                    }
                }
            }
        }

        return nil
    }

    /// Flat list of "Abbreviation Grade" pairs most useful for display.
    /// Prefers `officialRank.select` (user-selected datasets) then `customRank`.
    var displayRanks: [(label: String, value: String)] {
        var result: [(String, String)] = []

        // 1. Official — user's selected datasets
        if let select = officialRank?.select {
            for (key, value) in select where !value.isEmpty {
                result.append((EasyScholarRankProvider.abbreviationName(for: key), value))
            }
        }

        // 2. Custom datasets
        if let custom = customRank, let rankInfo = custom.rankInfo, let ranks = custom.rank {
            let infoByUUID = Dictionary(uniqueKeysWithValues: rankInfo.map { ($0.uuid, $0) })
            for rankEntry in ranks {
                let parts = rankEntry.split(separator: "&&&", omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let level = Int(parts[1]),
                      let info = infoByUUID[String(parts[0])] else { continue }
                let text: String? = {
                    switch level {
                    case 1: return info.oneRankText
                    case 2: return info.twoRankText
                    case 3: return info.threeRankText
                    case 4: return info.fourRankText
                    case 5: return info.fiveRankText
                    default: return nil
                    }
                }()
                if let text, !text.isEmpty {
                    result.append((info.abbName, text))
                }
            }
        }

        return result
    }
}

public extension EasyScholarRankProvider {
    /// Map official-rank abbreviation keys to human-readable labels.
    static func abbreviationName(for key: String) -> String {
        switch key.lowercased() {
        case "swufe": return "西南财经"
        case "cufe":  return "中央财经"
        case "uibe":  return "对外经贸"
        case "sdufe": return "山东财经"
        case "xdu":   return "西安电子"
        case "swjtu": return "西南交通"
        case "ruc":   return "人民大学"
        case "xmu":   return "厦门大学"
        case "sjtu":  return "上海交通"
        case "fdu":   return "复旦大学"
        case "hhu":   return "河海大学"
        case "pku":   return "北大核心"
        case "scu":   return "四川大学"
        case "cqu":   return "重庆大学"
        case "nju":   return "南京大学"
        case "xju":   return "新疆大学"
        case "cug":   return "中国地质"
        case "cju":   return "长江大学"
        case "zju":   return "浙江大学"
        case "zhongguokejihexin": return "中国科技核心"
        case "cssci": return "CSSCI"
        case "sci":   return "SCI"
        case "ssci":  return "SSCI"
        case "sciif": return "SCI-IF"
        case "sciif5": return "SCI-IF5"
        case "jci":   return "JCI"
        case "sciup": return "中科院分区"
        case "scibase": return "中科院基础版"
        case "sciupsmall": return "中科院小类"
        case "sciuptop": return "中科院Top"
        case "sciwarn": return "中科院预警"
        case "fms":   return "FMS"
        case "ajg":   return "ABS"
        case "utd24": return "UTD24"
        case "ft50":  return "FT50"
        case "eii":   return "EI"
        case "cscd":  return "CSCD"
        case "ahci":  return "A&HCI"
        case "esi":   return "ESI"
        case "cpu":   return "中国药科"
        case "ccf":   return "CCF"
        default:      return key.uppercased()
        }
    }
}

// MARK: - Throttle

private actor AsyncThrottle {
    private var lastRequest: Date = .distantPast
    private let interval: TimeInterval

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func wait() async {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequest)
        if elapsed < interval {
            let delay = interval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequest = Date()
    }
}
