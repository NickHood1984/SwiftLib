import Foundation
import GRDB

// MARK: - Health Stats Types

public struct LibraryHealthStats: Sendable {

    public struct VerificationCounts: Sendable {
        public var verifiedAuto: Int = 0
        public var verifiedManual: Int = 0
        public var legacy: Int = 0
        public var pending: Int = 0      // candidate + blocked + seedOnly + rejectedAmbiguous
        public var enriching: Int = 0    // metadataEnriching

        public var verified: Int { verifiedAuto + verifiedManual }
        public var total: Int { verified + legacy + pending + enriching }
    }

    public struct CSLCounts: Sendable {
        public var complete: Int = 0
        public var incomplete: Int = 0
        public var critical: Int = 0
        public var sampleSize: Int = 0   // refs scanned (may be capped)
        public var total: Int { complete + incomplete + critical }
    }

    public struct FieldMissingStat: Sendable {
        public var fieldKey: String
        public var displayName: String
        public var criticalCount: Int
        public var recommendedCount: Int
        public var totalCount: Int { criticalCount + recommendedCount }
    }

    public struct SourceStat: Sendable {
        public var sourceName: String
        public var count: Int
    }

    public var totalCount: Int
    public var verification: VerificationCounts
    public var csl: CSLCounts
    public var topMissingFields: [FieldMissingStat]   // sorted by totalCount desc, top 8
    public var sourceCounts: [SourceStat]              // sorted by count desc
}

// MARK: - Database Query

extension AppDatabase {

    /// Computes library health statistics. Runs SQL aggregates for counts and
    /// scans up to `cslSampleLimit` references for CSL field analysis.
    public func computeLibraryHealthStats(cslSampleLimit: Int = 3000) throws -> LibraryHealthStats {
        try dbWriter.read { db in
            // ── Total count ──
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reference") ?? 0

            // ── Verification status breakdown ──
            var verif = LibraryHealthStats.VerificationCounts()
            let verifRows = try Row.fetchAll(db, sql: """
                SELECT verificationStatus, COUNT(*) AS cnt
                FROM reference
                GROUP BY verificationStatus
                """)
            for row in verifRows {
                let status = VerificationStatus(rawValue: row["verificationStatus"] as? String ?? "") ?? .legacy
                let cnt: Int = row["cnt"]
                switch status {
                case .verifiedAuto:       verif.verifiedAuto += cnt
                case .verifiedManual:     verif.verifiedManual += cnt
                case .legacy:             verif.legacy += cnt
                case .metadataEnriching:  verif.enriching += cnt
                case .candidate, .blocked, .seedOnly, .rejectedAmbiguous:
                    verif.pending += cnt
                }
            }

            // ── Metadata source distribution ──
            let sourceRows = try Row.fetchAll(db, sql: """
                SELECT COALESCE(metadataSource, '手动录入') AS src, COUNT(*) AS cnt
                FROM reference
                GROUP BY metadataSource
                ORDER BY cnt DESC
                LIMIT 12
                """)
            let sourceCounts: [LibraryHealthStats.SourceStat] = sourceRows.map { row in
                let raw: String = row["src"]
                let display = MetadataSource(rawValue: raw)?.displayName ?? raw
                return .init(sourceName: display, count: row["cnt"])
            }

            // ── CSL field completeness (in-memory scan, capped) ──
            let refs = try Reference
                .order(Reference.Columns.dateAdded.desc)
                .limit(cslSampleLimit)
                .fetchAll(db)

            var csl = LibraryHealthStats.CSLCounts()
            csl.sampleSize = refs.count
            var fieldCritical: [String: (name: String, count: Int)] = [:]
            var fieldRecommended: [String: (name: String, count: Int)] = [:]

            for ref in refs {
                let issues = ref.cslFieldIssues
                switch ref.cslCompleteness {
                case .complete:   csl.complete += 1
                case .incomplete: csl.incomplete += 1
                case .critical:   csl.critical += 1
                }
                for issue in issues {
                    switch issue.severity {
                    case .critical:
                        fieldCritical[issue.fieldKey, default: (issue.displayName, 0)].count += 1
                    case .recommended:
                        fieldRecommended[issue.fieldKey, default: (issue.displayName, 0)].count += 1
                    }
                }
            }

            // Merge into top missing fields list
            let allKeys = Set(fieldCritical.keys).union(fieldRecommended.keys)
            let topMissing: [LibraryHealthStats.FieldMissingStat] = allKeys
                .map { key in
                    let crit = fieldCritical[key]
                    let rec  = fieldRecommended[key]
                    let name = crit?.name ?? rec?.name ?? key
                    return LibraryHealthStats.FieldMissingStat(
                        fieldKey: key,
                        displayName: name,
                        criticalCount: crit?.count ?? 0,
                        recommendedCount: rec?.count ?? 0
                    )
                }
                .sorted { $0.totalCount > $1.totalCount }
                .prefix(8)
                .map { $0 }

            return LibraryHealthStats(
                totalCount: total,
                verification: verif,
                csl: csl,
                topMissingFields: topMissing,
                sourceCounts: sourceCounts
            )
        }
    }
}
