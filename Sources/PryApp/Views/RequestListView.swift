import SwiftUI
import AppKit
import PryKit
import PryLib

@available(macOS 14, *)
struct RequestListView: NSViewRepresentable {
    @Environment(RequestStoreWrapper.self) private var store
    @Environment(ProxyManager.self) private var proxy

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, addDomain: { [proxy] d in proxy.addDomain(d) },
                                  removeDomain: { [proxy] d in proxy.removeDomain(d) })
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
            ("time", "Time", 65),
            ("duration", "Duration", 72),
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

        // Context menu
        tableView.menu = context.coordinator.makeContextMenu()

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.store = store
        coordinator.addDomain = { [proxy] d in proxy.addDomain(d) }
        coordinator.removeDomain = { [proxy] d in proxy.removeDomain(d) }

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
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var requests: [RequestStore.CapturedRequest] = []
        // Weak reference to avoid retaining an obsolete store when SwiftUI
        // recreates the representable but the NSView persists.
        weak var store: RequestStoreWrapper?
        var selectedId: Int?
        weak var tableView: NSTableView?
        var addDomain: (String) -> Void
        var removeDomain: (String) -> Void
        var hoveredRow: Int = -1

        init(store: RequestStoreWrapper,
             addDomain: @escaping (String) -> Void,
             removeDomain: @escaping (String) -> Void) {
            self.store = store
            self.addDomain = addDomain
            self.removeDomain = removeDomain
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
                cell.textColor = Self.statusColor(req.statusCode)
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
            case "duration":
                cell.stringValue = Self.formatDuration(req.duration)
                cell.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                cell.textColor = req.duration == nil ? .tertiaryLabelColor : .secondaryLabelColor
                cell.alignment = .right
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

        // MARK: - Context menu

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        /// Rebuild the context menu just before it appears so items reflect
        /// the right-clicked row's current watchlist state.
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()

            guard let tableView,
                  tableView.clickedRow >= 0,
                  tableView.clickedRow < requests.count else { return }

            let req = requests[tableView.clickedRow]

            // SSL Proxying toggle
            let inWatchlist = Watchlist.matches(req.host)
            let sslTitle = inWatchlist ? "Disable SSL Proxying for \(req.host)" : "Enable SSL Proxying for \(req.host)"
            let sslItem = NSMenuItem(
                title: sslTitle,
                action: #selector(toggleSSL(_:)),
                keyEquivalent: "")
            sslItem.representedObject = req
            sslItem.target = self
            menu.addItem(sslItem)

            menu.addItem(.separator())

            // Copy URL
            let copyURLItem = NSMenuItem(
                title: "Copy URL",
                action: #selector(copyURL(_:)),
                keyEquivalent: "")
            copyURLItem.representedObject = req
            copyURLItem.target = self
            menu.addItem(copyURLItem)

            // Copy as cURL
            let curlItem = NSMenuItem(
                title: "Copy as cURL",
                action: #selector(copyAsCurl(_:)),
                keyEquivalent: "")
            curlItem.representedObject = req
            curlItem.target = self
            menu.addItem(curlItem)

            // Copy Host
            let copyHostItem = NSMenuItem(
                title: "Copy Host",
                action: #selector(copyHost(_:)),
                keyEquivalent: "")
            copyHostItem.representedObject = req
            copyHostItem.target = self
            menu.addItem(copyHostItem)
        }

        @objc private func toggleSSL(_ sender: NSMenuItem) {
            guard let req = sender.representedObject as? RequestStore.CapturedRequest else { return }
            if Watchlist.matches(req.host) {
                removeDomain(req.host)
            } else {
                addDomain(req.host)
            }
        }

        @objc private func copyURL(_ sender: NSMenuItem) {
            guard let req = sender.representedObject as? RequestStore.CapturedRequest else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(req.url, forType: .string)
        }

        @objc private func copyAsCurl(_ sender: NSMenuItem) {
            guard let req = sender.representedObject as? RequestStore.CapturedRequest else { return }
            let curl = CurlGenerator.generate(from: req)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(curl, forType: .string)
        }

        @objc private func copyHost(_ sender: NSMenuItem) {
            guard let req = sender.representedObject as? RequestStore.CapturedRequest else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(req.host, forType: .string)
        }

        private static let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f
        }()

        static func formatTime(_ date: Date) -> String {
            timeFormatter.string(from: date)
        }

        static func formatDuration(_ duration: TimeInterval?) -> String {
            guard let d = duration else { return "—" }
            if d < 1 {
                return "\(Int(d * 1000))ms"
            } else {
                return String(format: "%.1fs", d)
            }
        }

        static func statusColor(_ code: UInt?) -> NSColor {
            guard let code else { return .secondaryLabelColor }
            switch code {
            case 200..<300: return NSColor(red: 0.13, green: 0.68, blue: 0.38, alpha: 1) // green
            case 300..<400: return NSColor(red: 0.90, green: 0.65, blue: 0.07, alpha: 1) // amber
            case 400..<500: return NSColor(red: 0.95, green: 0.38, blue: 0.29, alpha: 1) // red-orange
            case 500...:    return NSColor(red: 0.80, green: 0.10, blue: 0.10, alpha: 1) // dark red
            default:        return .secondaryLabelColor
            }
        }

        // MARK: - Hover highlight (#61)

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("rowView"), owner: nil) as? HoverRowView
                ?? HoverRowView()
            rowView.identifier = NSUserInterfaceItemIdentifier("rowView")
            return rowView
        }
    }
}

/// NSTableRowView subclass that highlights on mouse hover.
final class HoverRowView: NSTableRowView {
    var isHovered = false {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovered && !isSelected {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            dirtyRect.fill()
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
