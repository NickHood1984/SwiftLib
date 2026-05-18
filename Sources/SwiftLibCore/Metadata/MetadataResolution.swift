import Foundation
import OSLog

public enum MetadataResolution {
    static let metadataLog = Logger(subsystem: "com.swiftlib.metadata", category: "resolution")

    public static let candidateThreshold = 0.52
    public static let automaticCandidateThreshold = 0.85
    public static let automaticCandidateMargin = 0.10
    // CNKI 专用阈值：中文标题相似度因副标题、标点差异等原因系统性偏低，适当放宽
    public static let cnkiCandidateThreshold = 0.45  // 原等于 candidateThreshold (0.52)
    public static let automaticCNKIRefreshThreshold = 0.78  // 原等于 automaticCandidateThreshold (0.85)
}
