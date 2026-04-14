import SwiftUI
import PryKit

@available(macOS 14, *)
@MainActor
struct FilterBarView: View {
    @Environment(RequestStoreWrapper.self) private var store

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE"]
    private let statusRanges: [(label: String, range: ClosedRange<UInt>)] = [
        ("2xx", 200...299),
        ("3xx", 300...399),
        ("4xx", 400...499),
        ("5xx", 500...599),
    ]

    var body: some View {
        @Bindable var store = store

        HStack(spacing: 8) {
            // Search field first — prominent, takes most space
            SearchFieldView(text: $store.filterText, placeholder: "Filter path, host or body...")
                .frame(maxHeight: 24)

            Spacer()

            // Method filter — icon style
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
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 10))
                    Text(store.filterMethod ?? "Method")
                        .font(.system(size: 11, weight: store.filterMethod != nil ? .semibold : .regular))
                }
                .foregroundStyle(store.filterMethod != nil ? PryTheme.accent : PryTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(store.filterMethod != nil ? PryTheme.accent.opacity(0.12) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.borderless)

            // Status filter — icon style
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
                HStack(spacing: 4) {
                    Image(systemName: "circle.grid.2x1")
                        .font(.system(size: 10))
                    Text(activeLabel ?? "Status")
                        .font(.system(size: 11, weight: activeLabel != nil ? .semibold : .regular))
                }
                .foregroundStyle(store.filterStatus != nil ? PryTheme.accent : PryTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(store.filterStatus != nil ? PryTheme.accent.opacity(0.12) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.borderless)

            // Clear all
            let hasActive = store.filterMethod != nil ||
                            store.filterStatus != nil ||
                            !store.filterText.isEmpty
            if hasActive {
                Button {
                    store.filterMethod = nil
                    store.filterStatus = nil
                    store.filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(PryTheme.textTertiary)
                }
                .buttonStyle(.borderless)
                .help("Clear all filters")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PryTheme.bgHeader)
        // Cmd+F focuses the search field
        .onKeyPress(.init("f"), phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            if let field = SearchFieldView.activeField {
                field.window?.makeFirstResponder(field)
            }
            return .handled
        }
    }
}
