import SwiftUI
import PryKit

@available(macOS 14, *)
@MainActor
struct FilterBarView: View {
    @Environment(RequestStoreWrapper.self) private var store
    @FocusState private var searchFocused: Bool

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE"]
    private let statusRanges: [(label: String, range: ClosedRange<UInt>)] = [
        ("2xx", 200...299),
        ("3xx", 300...399),
        ("4xx", 400...499),
        ("5xx", 500...599),
    ]

    var body: some View {
        @Bindable var store = store

        HStack(spacing: 4) {
            // Method picker — compact menu instead of 5 chips
            Menu {
                Button("All Methods") { store.filterMethod = nil }
                Divider()
                ForEach(methods, id: \.self) { method in
                    Button {
                        store.filterMethod = store.filterMethod == method ? nil : method
                    } label: {
                        HStack {
                            Text(method)
                            if store.filterMethod == method {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(store.filterMethod ?? "Method")
                        .font(.system(size: 11, weight: store.filterMethod != nil ? .semibold : .regular))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(store.filterMethod != nil ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.borderless)

            // Status picker — compact menu instead of 4 chips
            Menu {
                Button("All Status") { store.filterStatus = nil }
                Divider()
                ForEach(statusRanges, id: \.label) { entry in
                    Button {
                        store.filterStatus = store.filterStatus == entry.range ? nil : entry.range
                    } label: {
                        HStack {
                            Text(entry.label)
                            if store.filterStatus == entry.range {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let activeLabel = statusRanges.first(where: { $0.range == store.filterStatus })?.label
                HStack(spacing: 3) {
                    Text(activeLabel ?? "Status")
                        .font(.system(size: 11, weight: activeLabel != nil ? .semibold : .regular))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(store.filterStatus != nil ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.borderless)

            Divider().frame(height: 14)

            // Search field — native NSSearchField so it gets focus alongside NSTableView
            SearchFieldView(text: $store.filterText)
                .frame(minWidth: 120, maxHeight: 22)

            // Clear all filters
            let hasActive = store.filterMethod != nil ||
                            store.filterStatus != nil ||
                            !store.filterText.isEmpty
            if hasActive {
                Button {
                    store.filterMethod = nil
                    store.filterStatus = nil
                    store.filterText = ""
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear all filters")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(PryTheme.bgHeader)
        // Cmd+F focuses the search field
        .onKeyPress(.init("f"), phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            searchFocused = true
            return .handled
        }
    }
}
