import SwiftUI
import Combine
import SwiftLibCore

struct PendingMetadataQueueView: View {
    let db: AppDatabase
    let resolver: MetadataResolver
    let onPersistResult: (MetadataResolutionResult, MetadataIntake) -> Void
    let onConfirmManual: (MetadataIntake) -> Void
    let onDelete: (MetadataIntake) -> Void

    @State private var workingIntakeID: Int64?
    @State private var expandedIntakeID: Int64?
    @State private var intakes: [MetadataIntake] = []

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            if intakes.isEmpty {
                emptyState
            } else {
                queueContent
            }
        }
        .frame(width: 720, height: 520)
        // 订阅 DB observer，队列变化时自动刷新窗口内容
        .onReceive(
            db.observePendingMetadataIntakes()
                .receive(on: DispatchQueue.main)
                .replaceError(with: [])
        ) { items in
            intakes = items
            // 若当前展开或正在工作的条目已被移出队列，清除其本地状态
            if let expanded = expandedIntakeID,
               !items.contains(where: { $0.id == expanded }) {
                expandedIntakeID = nil
            }
            if let working = workingIntakeID,
               !items.contains(where: { $0.id == working }) {
                workingIntakeID = nil
            }
        }
    }

    private var queueContent: some View {
        VStack(spacing: 0) {
            queueHeader

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(intakes) { intake in
                        IntakeRow(
                            intake: intake,
                            isWorking: workingIntakeID == intake.id,
                            isExpanded: expandedIntakeID == intake.id,
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedIntakeID = (expandedIntakeID == intake.id) ? nil : intake.id
                                }
                            },
                            onUseCandidate: { candidate in
                                resolveCandidate(candidate, intake: intake)
                            },
                            onConfirmManual: {
                                onConfirmManual(intake)
                            },
                            onRetry: {
                                retry(intake)
                            },
                            onDelete: {
                                onDelete(intake)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .swiftLibElegantScrollers()
        }
    }

    private var queueHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("待确认元数据")
                .font(.title3.weight(.semibold))
            Text("\(intakes.count) 条")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(.leading, 78)
        .padding(.trailing, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.green)
            }
            Text("所有元数据已确认")
                .font(.title3.weight(.semibold))
            Text("暂无可确认的候选条目")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retry(_ intake: MetadataIntake) {
        workingIntakeID = intake.id
        Task { @MainActor in
            let result = await resolver.retryIntake(intake)
            onPersistResult(result, intake)
            workingIntakeID = nil
        }
    }

    private func resolveCandidate(_ candidate: MetadataCandidate, intake: MetadataIntake) {
        workingIntakeID = intake.id
        expandedIntakeID = nil
        Task { @MainActor in
            let result = await resolver.resolveCandidate(
                candidate,
                fallback: intake.decodedFallbackReference ?? intake.decodedCurrentReference,
                seed: intake.decodedSeed,
                treatingManualSelectionAsConfirmation: true,
                reviewedBy: "candidate-selection"
            )
            onPersistResult(result, intake)
            workingIntakeID = nil
        }
    }
}

// MARK: - IntakeRow

private struct IntakeRow: View {
    let intake: MetadataIntake
    let isWorking: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onUseCandidate: (MetadataCandidate) -> Void
    let onConfirmManual: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void

    private var candidates: [MetadataCandidate] { intake.decodedCandidates }
    private var bestCandidate: MetadataCandidate? { candidates.first }
    private var otherCandidates: [MetadataCandidate] { candidates.count > 1 ? Array(candidates.dropFirst()) : [] }

    private var bestAssessment: ManualCandidateImportAssessment? {
        guard let c = bestCandidate else { return nil }
        return MetadataResolver.assessManuallyConfirmedCandidate(
            c,
            fallback: intake.decodedFallbackReference ?? intake.decodedCurrentReference
        )
    }

    /// Whether this intake is in a state that has no authoritative metadata
    /// (seed-only or ambiguously rejected). These rows get a lighter visual
    /// treatment and inline retry/remove icons.
    private var isUnresolvedStatus: Bool {
        switch intake.verificationStatus {
        case .seedOnly, .rejectedAmbiguous:
            return true
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 条目头部：标题 + 来源角标 + 操作菜单
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(intake.title)
                        .font(.headline)
                        .lineLimit(2)
                    // 有候选时在标题下方显示分数/来源，隐藏冗余的状态消息
                    if let best = bestCandidate {
                        HStack(spacing: 5) {
                            Text("最佳匹配")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.14), in: Capsule())
                                .foregroundStyle(.blue)
                            if best.score > 0 {
                                Text("\(Int(best.score * 100))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(best.source.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if let message = intake.statusMessage?.swiftlib_nilIfBlank {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isWorking {
                    ProgressView().controlSize(.small).padding(.top, 2)
                } else if isUnresolvedStatus {
                    HStack(spacing: 10) {
                        Button { onRetry() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("重试")
                        Button { onDelete() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("移除")
                    }
                } else {
                    Menu {
                        Button("重试") { onRetry() }
                        Divider()
                        Button("移除", role: .destructive) { onDelete() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, bestCandidate != nil ? 10 : 12)

            // ── 最佳候选卡片
            if let best = bestCandidate {
                CandidateCard(
                    candidate: best,
                    assessment: bestAssessment,
                    isBest: true,
                    isWorking: isWorking,
                    onUse: { onUseCandidate(best) }
                )
                .padding(.horizontal, 10)
                .padding(.bottom, otherCandidates.isEmpty ? 12 : 8)

                // ── 展开更多候选
                if !otherCandidates.isEmpty {
                    Button {
                        onToggleExpand()
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "收起其他候选" : "还有 \(otherCandidates.count) 个候选结果")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.bottom, isExpanded ? 8 : 12)

                    if isExpanded {
                        VStack(spacing: 8) {
                            ForEach(otherCandidates) { candidate in
                                let assessment = MetadataResolver.assessManuallyConfirmedCandidate(
                                    candidate,
                                    fallback: intake.decodedFallbackReference ?? intake.decodedCurrentReference
                                )
                                CandidateCard(
                                    candidate: candidate,
                                    assessment: assessment,
                                    isBest: false,
                                    isWorking: isWorking,
                                    onUse: { onUseCandidate(candidate) }
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } else if let reference = intake.bestAvailableReference {
                switch intake.verificationStatus {
                case .seedOnly, .rejectedAmbiguous:
                    // 没有找到权威元数据或结果不明确——不应提供"确认导入"，
                    // 因为 bestAvailableReference 此时只是原始 seed，没有新增可确认信息。
                    HStack {
                        Text(intake.verificationStatus == .seedOnly
                             ? "未找到权威元数据"
                             : "结果不明确，建议重试")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                default:
                    // 其他情况——显示确认导入按钮
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if !reference.authors.isEmpty {
                                Text(reference.authors.displayString)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            let meta = [reference.journal, reference.year.map(String.init)]
                                .compactMap { $0 }.joined(separator: " · ")
                            if !meta.isEmpty {
                                Text(meta).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 0)
                        Button("确认导入") { onConfirmManual() }
                            .buttonStyle(SLPrimaryButtonStyle())
                            .controlSize(.small)
                            .disabled(isWorking)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isUnresolvedStatus
                      ? Color.secondary.opacity(0.03)
                      : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isUnresolvedStatus
                              ? Color.primary.opacity(0.04)
                              : Color.primary.opacity(0.07),
                              lineWidth: 1)
        )
    }
}

// MARK: - CandidateCard

private struct CandidateCard: View {
    let candidate: MetadataCandidate
    let assessment: ManualCandidateImportAssessment?
    let isBest: Bool
    let isWorking: Bool
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题行 — 最佳候选已在外层行头展示，此处只在其他候选卡中重复显示
            if !isBest {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(candidate.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if candidate.score > 0 {
                        Text("\(Int(candidate.score * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(candidate.source.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // 作者
            if !candidate.authors.isEmpty {
                Text(candidate.authors.displayString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // 期刊/年份
            let detailLine = [candidate.journal, candidate.year.map(String.init)]
                .compactMap { $0 }.joined(separator: " · ")
            if !detailLine.isEmpty {
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 类型
            let typeStr = candidate.referenceType?.rawValue
                ?? (candidate.workKind == .unknown ? "" : candidate.workKind.referenceType.rawValue)
            if !typeStr.isEmpty {
                Text(typeStr).font(.caption).foregroundStyle(.tertiary)
            }

            // 摘要
            if let snippet = candidate.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // 信息评估 + 使用按钮
            HStack(alignment: .bottom, spacing: 8) {
                if let assessment {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            assessment.canImportDirectly
                                ? "信息已齐，可直接导入"
                                : "还缺：\(assessment.missingFields.joined(separator: " / "))"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(assessment.canImportDirectly ? .green : .orange)
                        if !assessment.presentFields.isEmpty {
                            Text("已有：\(assessment.presentFields.joined(separator: " / "))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if !candidate.matchedBy.isEmpty {
                            Text("匹配: \(candidate.matchedBy.joined(separator: " / "))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button("使用此条") { onUse() }
                    .buttonStyle(SLPrimaryButtonStyle())
                    .controlSize(.small)
                    .disabled(isWorking)
            }
        }
        .padding(12)
        .background(
            isBest
                ? Color.accentColor.opacity(0.08)
                : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isBest ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
    }
}
