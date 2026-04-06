import SwiftUI
import PryKit

@available(macOS 14, *)
@MainActor
struct FilterBarView: View {
    @Environment(RequestStoreWrapper.self) private var store

    private let methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
    private let statusRanges: [(label: String, range: ClosedRange<UInt>)] = [
        ("2xx", 200...299),
        ("3xx", 300...399),
        ("4xx", 400...499),
        ("5xx", 500...599),
    ]

    var body: some View {
        @Bindable var store = store

        HStack(spacing: 6) {
            // Method chips
            ForEach(methods, id: \.self) { method in
                FilterChip(
                    title: method,
                    isActive: store.filterMethod == method
                ) {
                    store.filterMethod = store.filterMethod == method ? nil : method
                }
            }

            Divider().frame(height: 16)

            // Status chips
            ForEach(statusRanges, id: \.label) { entry in
                FilterChip(
                    title: entry.label,
                    isActive: store.filterStatus == entry.range
                ) {
                    store.filterStatus = store.filterStatus == entry.range ? nil : entry.range
                }
            }

            Divider().frame(height: 16)

            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter...", text: $store.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !store.filterText.isEmpty {
                    Button {
                        store.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 200)

            Spacer()

            // Active filters indicator — computed inline for @Bindable consistency
            let hasActive = store.filterMethod != nil ||
                            store.filterStatus != nil ||
                            !store.filterText.isEmpty
            if hasActive {
                Button("Clear Filters") {
                    store.filterMethod = nil
                    store.filterStatus = nil
                    store.filterText = ""
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
