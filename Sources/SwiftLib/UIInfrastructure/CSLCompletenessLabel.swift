import SwiftUI
import SwiftLibCore

/// A pill-shaped badge showing CSL field completeness for a reference.
/// Tapping it shows a popover listing any missing fields.
struct CSLCompletenessLabel: View {
    let reference: Reference

    @State private var showPopover = false

    private var issues: [CSLFieldIssue] { reference.cslFieldIssues }
    private var completeness: CSLCompleteness { reference.cslCompleteness }

    var body: some View {
        Button {
            if !issues.isEmpty { showPopover = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .semibold))
                Text(labelText)
                    .font(.caption)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            CSLCompletenessPopover(issues: issues)
        }
    }

    private var iconName: String {
        switch completeness {
        case .complete:    return "checkmark.circle.fill"
        case .incomplete:  return "exclamationmark.circle.fill"
        case .critical:    return "xmark.circle.fill"
        }
    }

    private var labelText: String {
        switch completeness {
        case .complete:   return "字段完整"
        case .incomplete: return "建议补全"
        case .critical:   return "缺必填字段"
        }
    }

    private var foregroundColor: Color {
        switch completeness {
        case .complete:   return .green
        case .incomplete: return .orange
        case .critical:   return .red
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }
}

private struct CSLCompletenessPopover: View {
    let issues: [CSLFieldIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("引用字段状态")
                .font(.headline)
                .padding(.bottom, 2)

            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                HStack(spacing: 8) {
                    Image(systemName: issue.severity == .critical ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(issue.severity == .critical ? .red : .orange)
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(issue.displayName)
                            .font(.callout)
                        Text(issue.severity == .critical ? "多数引用样式必需" : "部分引用样式需要")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if issues.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("所有常用字段均已填写")
                        .font(.callout)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 220)
    }
}
