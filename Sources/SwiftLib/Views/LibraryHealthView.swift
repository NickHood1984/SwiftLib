import SwiftUI
import SwiftLibCore

struct LibraryHealthView: View {
    @State private var stats: LibraryHealthStats? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("正在分析文献库…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let msg = errorMessage {
                    Text("分析失败：\(msg)")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let s = stats {
                    statCards(s)
                    Divider()
                    verificationSection(s.verification)
                    Divider()
                    cslSection(s.csl)
                    if !s.topMissingFields.isEmpty {
                        Divider()
                        missingFieldsSection(s.topMissingFields)
                    }
                    if !s.sourceCounts.isEmpty {
                        Divider()
                        sourcesSection(s.sourceCounts)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 420)
        .navigationTitle("文献库体检")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadStats() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await loadStats() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func statCards(_ s: LibraryHealthStats) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatCard(value: "\(s.totalCount)", label: "总条目", color: .primary)
            StatCard(value: "\(s.verification.verified)", label: "已验证", color: .green)
            StatCard(value: "\(s.csl.critical)", label: "CSL 缺必填", color: s.csl.critical > 0 ? .red : .secondary)
            StatCard(value: "\(s.verification.pending)", label: "待确认", color: s.verification.pending > 0 ? .orange : .secondary)
        }
    }

    @ViewBuilder
    private func verificationSection(_ v: LibraryHealthStats.VerificationCounts) -> some View {
        SectionHeader(title: "验证状态", systemImage: "checkmark.shield")
        let total = max(v.total, 1)
        VStack(spacing: 8) {
            BarRow(label: "自动验证", count: v.verifiedAuto, total: total, color: .green)
            BarRow(label: "人工确认", count: v.verifiedManual, total: total, color: Color(red: 0.1, green: 0.7, blue: 0.4))
            BarRow(label: "历史条目", count: v.legacy, total: total, color: .secondary)
            if v.enriching > 0 {
                BarRow(label: "补全中", count: v.enriching, total: total, color: .blue)
            }
            if v.pending > 0 {
                BarRow(label: "待确认队列", count: v.pending, total: total, color: .orange)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func cslSection(_ c: LibraryHealthStats.CSLCounts) -> some View {
        let subtitle = c.sampleSize < (stats?.totalCount ?? 0)
            ? "（已扫描 \(c.sampleSize) 条，按导入时间倒序）"
            : ""
        SectionHeader(title: "引用字段完整度\(subtitle)", systemImage: "doc.text.magnifyingglass")
        let total = max(c.total, 1)
        VStack(spacing: 8) {
            BarRow(label: "字段完整", count: c.complete, total: total, color: .green)
            BarRow(label: "建议补全", count: c.incomplete, total: total, color: .orange)
            BarRow(label: "缺必填字段", count: c.critical, total: total, color: .red)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func missingFieldsSection(_ fields: [LibraryHealthStats.FieldMissingStat]) -> some View {
        SectionHeader(title: "最常缺失字段", systemImage: "exclamationmark.triangle")
        VStack(spacing: 6) {
            ForEach(fields, id: \.fieldKey) { f in
                HStack(spacing: 10) {
                    Text(f.displayName)
                        .font(.callout)
                        .frame(width: 90, alignment: .leading)
                    if f.criticalCount > 0 {
                        Label("\(f.criticalCount) 必填", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if f.recommendedCount > 0 {
                        Label("\(f.recommendedCount) 建议", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("共 \(f.totalCount) 条")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func sourcesSection(_ sources: [LibraryHealthStats.SourceStat]) -> some View {
        SectionHeader(title: "元数据来源分布", systemImage: "network")
        let maxCount = sources.map(\.count).max() ?? 1
        VStack(spacing: 8) {
            ForEach(sources, id: \.sourceName) { s in
                BarRow(label: s.sourceName, count: s.count, total: max(maxCount, 1), color: .accentColor)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Data loading

    @MainActor
    private func loadStats() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try AppDatabase.shared.computeLibraryHealthStats()
            }.value
            stats = result
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Sub-components

private struct StatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
    }
}

private struct BarRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    private var fraction: Double { Double(count) / Double(max(total, 1)) }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(NSColor.separatorColor).opacity(0.2))
                    Capsule().fill(color.opacity(0.75))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 10)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
            Text(String(format: "%.0f%%", fraction * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}
