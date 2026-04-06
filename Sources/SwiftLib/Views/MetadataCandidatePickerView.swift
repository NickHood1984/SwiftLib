import SwiftUI
import SwiftLibCore

struct MetadataCandidatePickerView: View {
    var title: String = "找到多个元数据候选"
    var message: String = "请选择要导入的元数据。"
    var skipLabel: String = "跳过"
    let candidates: [MetadataCandidate]
    var assessmentByCandidateID: [MetadataCandidate.ID: ManualCandidateImportAssessment] = [:]
    let onImportSelected: (MetadataCandidate) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @State private var selectedCandidateID: MetadataCandidate.ID?

    private var selectedCandidate: MetadataCandidate? {
        candidates.first { $0.id == selectedCandidateID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)

            List(candidates, selection: $selectedCandidateID) { candidate in
                VStack(alignment: .leading, spacing: 6) {
                    let assessment = assessmentByCandidateID[candidate.id]
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(candidate.title)
                            .font(.headline)
                        Spacer(minLength: 0)
                        if candidate.id == candidates.first?.id {
                            Text("最佳匹配")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.12), in: Capsule())
                        }
                        if candidate.score > 0 {
                            Text("\(Int(candidate.score * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(candidate.source.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !candidate.authors.isEmpty {
                        Text(candidate.authors.displayString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    let detailLine = [candidate.journal, candidate.year.map(String.init)]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    let publisherLine = [candidate.publisher, candidate.isbn, candidate.issn]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    if !detailLine.isEmpty {
                        Text(detailLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    let type = candidate.referenceType?.rawValue
                        ?? (candidate.workKind == .unknown ? "" : candidate.workKind.referenceType.rawValue)
                    if !type.isEmpty {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !publisherLine.isEmpty {
                        Text(publisherLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let snippet = candidate.snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let assessment {
                        VStack(alignment: .leading, spacing: 3) {
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
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        if !candidate.matchedBy.isEmpty {
                            Text("匹配: \(candidate.matchedBy.joined(separator: " / "))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("使用此条") {
                            onImportSelected(candidate)
                        }
                        .buttonStyle(SLPrimaryButtonStyle())
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
                .tag(candidate.id)
            }
            .frame(minWidth: 640, minHeight: 320)

            HStack {
                Button("取消", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(skipLabel, action: onSkip)

                Button("导入所选结果") {
                    guard let selectedCandidate else { return }
                    onImportSelected(selectedCandidate)
                }
                .buttonStyle(SLPrimaryButtonStyle())
                .disabled(selectedCandidate == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 460)
        .onAppear {
            selectedCandidateID = candidates.first?.id
        }
    }
}
