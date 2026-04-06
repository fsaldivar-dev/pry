import SwiftUI
import PryLib

@available(macOS 14, *)
@MainActor
struct DiffView: View {
    let requestA: RequestStore.CapturedRequest
    let requestB: RequestStore.CapturedRequest

    @State private var diffLines: [DiffTool.DiffLine] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("A: \(requestA.method) \(requestA.url)")
                        .font(.system(size: 11, design: .monospaced))
                    Text(requestA.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("B: \(requestB.method) \(requestB.url)")
                        .font(.system(size: 11, design: .monospaced))
                    Text(requestB.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            if diffLines.isEmpty {
                ContentUnavailableView(
                    "Requests are identical",
                    systemImage: "equal.circle",
                    description: Text("No differences found")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                            DiffLineView(line: line)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear {
            let lines = DiffTool.diff(req1: requestA, req2: requestB)
            // Filter out .same lines if all are same (identical)
            let hasChanges = lines.contains { line in
                switch line {
                case .same: return false
                default: return true
                }
            }
            diffLines = hasChanges ? lines : []
        }
    }
}

@available(macOS 14, *)
private struct DiffLineView: View {
    let line: DiffTool.DiffLine

    var body: some View {
        switch line {
        case .same(let text):
            Text("  \(text)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)

        case .added(let text):
            Text("+ \(text)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.1))

        case .removed(let text):
            Text("- \(text)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .background(Color.red.opacity(0.1))

        case .changed(let label, let left, let right):
            VStack(alignment: .leading, spacing: 0) {
                Text("~ \(label):")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Text("  - \(left)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red)
                Text("  + \(right)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.05))
        }
    }
}
