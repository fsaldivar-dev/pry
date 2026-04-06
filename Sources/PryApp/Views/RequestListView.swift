import SwiftUI
import AppKit
import PryKit
import PryLib

@available(macOS 14, *)
struct RequestListView: NSViewRepresentable {
    @Environment(RequestStoreWrapper.self) private var store

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        let columns: [(String, String, CGFloat)] = [
            ("icon", "", 30),
            ("method", "Method", 60),
            ("status", "Status", 55),
            ("host", "Host", 180),
            ("path", "Path", 250),
            ("time", "Time", 80),
        ]
        for (id, title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = id == "icon" ? 30 : 40
            tableView.addTableColumn(col)
        }

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.style = .inset
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.tableViewClicked(_:))

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.store = store

        let newRequests = store.filteredRequests

        // Compare by content signature — detects status updates, not just count
        let needsReload: Bool = {
            guard newRequests.count == coordinator.requests.count else { return true }
            for (new, old) in zip(newRequests, coordinator.requests) {
                if new.id != old.id || new.statusCode != old.statusCode { return true }
            }
            return false
        }()
        guard needsReload else { return }

        let selectedId = coordinator.selectedId
        coordinator.requests = newRequests
        coordinator.tableView?.reloadData()

        // Restore selection after reload
        if let id = selectedId,
           let idx = newRequests.firstIndex(where: { $0.id == id }) {
            coordinator.tableView?.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var requests: [RequestStore.CapturedRequest] = []
        // Weak reference to avoid retaining an obsolete store when SwiftUI
        // recreates the representable but the NSView persists.
        weak var store: RequestStoreWrapper?
        var selectedId: Int?
        weak var tableView: NSTableView?

        init(store: RequestStoreWrapper) {
            self.store = store
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            requests.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < requests.count, let colId = tableColumn?.identifier.rawValue else { return nil }
            let req = requests[row]

            let cellId = NSUserInterfaceItemIdentifier(colId)
            let cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField
                ?? NSTextField(labelWithString: "")
            cell.identifier = cellId
            cell.lineBreakMode = .byTruncatingTail

            switch colId {
            case "icon":
                cell.stringValue = RequestIconHelper.icon(for: req)
                cell.alignment = .center
            case "method":
                cell.stringValue = req.method
                cell.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            case "status":
                cell.stringValue = req.statusCode.map { "\($0)" } ?? "..."
                cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            case "host":
                cell.stringValue = req.host
                cell.font = .systemFont(ofSize: 11)
            case "path":
                cell.stringValue = req.url
                cell.font = .systemFont(ofSize: 11)
            case "time":
                cell.stringValue = Self.formatTime(req.timestamp)
                cell.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                cell.textColor = .secondaryLabelColor
            default:
                break
            }
            return cell
        }

        @objc func tableViewClicked(_ sender: NSTableView) {
            let row = sender.selectedRow
            if row >= 0, row < requests.count {
                let req = requests[row]
                selectedId = req.id
                store?.selectedRequest = req
            } else {
                selectedId = nil
                store?.selectedRequest = nil
            }
        }

        private static let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f
        }()

        static func formatTime(_ date: Date) -> String {
            timeFormatter.string(from: date)
        }
    }
}

enum RequestIconHelper {
    static func icon(for request: RequestStore.CapturedRequest) -> String {
        if request.isMock { return "🔮" }
        if request.isTunnel { return "🔒" }
        if request.isPinned { return "📌" }
        guard let status = request.statusCode else { return "⏳" }
        switch status {
        case 200..<300: return "🟢"
        case 300..<400: return "🟡"
        case 400..<600: return "🔴"
        default: return "⚪"
        }
    }
}
