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

        // (id, title, width, resizes?)
        let columns: [(String, String, CGFloat, Bool)] = [
            ("icon",     "",         28,  false),
            ("method",   "Method",   68,  false),
            ("status",   "Status",   56,  false),
            ("host",     "Host",     150, false),
            ("path",     "Path",     200, true),   // stretches to fill
            ("duration", "Duration", 64,  false),
            ("time",     "Time",     60,  false),
        ]
        for (id, title, width, resizes) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title.uppercased()
            col.width = width
            col.minWidth = id == "icon" ? 28 : 36
            col.resizingMask = resizes ? .autoresizingMask : .userResizingMask
            // Style column headers
            col.headerCell.font = .systemFont(ofSize: 9, weight: .semibold)
            col.headerCell.textColor = PryTheme.nsTextTertiary
            tableView.addTableColumn(col)
        }
        // Path stretches; fixed columns don't shrink below their width
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.sizeLastColumnToFit()

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridColor = NSColor.white.withAlphaComponent(0.06)
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 32  // More breathing room between rows
        tableView.style = .inset
        tableView.intercellSpacing = NSSize(width: 6, height: 6)
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.tableViewClicked(_:))

        // Context menu
        tableView.menu = context.coordinator.makeContextMenu()

        // Uniform dark background
        tableView.backgroundColor = PryTheme.nsBgMain
        scrollView.backgroundColor = PryTheme.nsBgMain
        scrollView.drawsBackground = true
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

        coordinator.tableView?.sizeLastColumnToFit()
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

            // Icon column: colored status dot
            if colId == "icon" {
                return Self.makeStatusDot(for: req, tableView: tableView)
            }

            // Method column: custom cell with badge
            if colId == "method" {
                return Self.makeMethodBadge(method: req.method, tableView: tableView)
            }

            // All other columns: vertically-centered NSTextField inside NSTableCellView
            let cellId = NSUserInterfaceItemIdentifier(colId)
            let cellView: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView,
               let tf = reused.textField {
                cellView = reused
                configure(textField: tf, colId: colId, req: req)
            } else {
                cellView = NSTableCellView()
                cellView.identifier = cellId
                let tf = NSTextField(labelWithString: "")
                tf.translatesAutoresizingMaskIntoConstraints = false
                tf.lineBreakMode = .byTruncatingTail
                tf.cell?.isScrollable = false
                tf.cell?.truncatesLastVisibleLine = true
                cellView.addSubview(tf)
                cellView.textField = tf
                // Center vertically, pin horizontally
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                    tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -2),
                    tf.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                ])
                configure(textField: tf, colId: colId, req: req)
            }
            return cellView
        }

        private func configure(textField tf: NSTextField, colId: String, req: RequestStore.CapturedRequest) {
            switch colId {
            case "status":
                tf.stringValue = req.statusCode.map { "\($0)" } ?? "..."
                tf.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
                tf.alignment = .center
                tf.textColor = PryTheme.statusColor(req.statusCode)
            case "host":
                tf.stringValue = req.host
                tf.font = .systemFont(ofSize: 11)
                tf.textColor = PryTheme.nsTextPrimary
            case "path":
                // Show relative path instead of full URL
                if let url = URL(string: req.url) {
                    let path = url.path.isEmpty ? "/" : url.path
                    let query = url.query.map { "?\($0)" } ?? ""
                    tf.stringValue = path + query
                } else {
                    tf.stringValue = req.url
                }
                tf.font = .systemFont(ofSize: 11)
                tf.textColor = PryTheme.nsTextPrimary
            case "time":
                tf.stringValue = Self.formatTime(req.timestamp)
                tf.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                tf.textColor = PryTheme.nsTextSecondary
            case "duration":
                tf.stringValue = Self.formatDuration(req.duration)
                tf.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                tf.textColor = req.duration == nil ? PryTheme.nsTextTertiary : PryTheme.nsTextSecondary
                tf.alignment = .right
            default:
                break
            }
        }

        /// Creates a method badge: NSTableCellView -> badgeView -> label, always centered.
        private static func makeMethodBadge(method: String, tableView: NSTableView) -> NSView {
            let cellId = NSUserInterfaceItemIdentifier("methodBadge")
            if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView {
                // Update existing badge
                if let badge = reused.subviews.first,
                   let label = badge.subviews.first as? NSTextField {
                    label.stringValue = method
                    let (textColor, bgColor) = methodColors(method)
                    label.textColor = textColor
                    badge.layer?.backgroundColor = bgColor.cgColor
                }
                return reused
            }

            // Build new badge cell
            let cellView = NSTableCellView()
            cellView.identifier = cellId

            // Badge background view
            let badge = NSView()
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 4
            badge.layer?.masksToBounds = true
            badge.translatesAutoresizingMaskIntoConstraints = false

            // Label inside badge
            let label = NSTextField(labelWithString: method)
            label.font = .systemFont(ofSize: 9, weight: .bold)
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false

            let (textColor, bgColor) = methodColors(method)
            label.textColor = textColor
            badge.layer?.backgroundColor = bgColor.cgColor

            badge.addSubview(label)
            cellView.addSubview(badge)

            // Badge centered in cell, label pinned inside badge with padding
            NSLayoutConstraint.activate([
                badge.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                badge.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
                badge.heightAnchor.constraint(equalToConstant: 20),
                label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            ])

            return cellView
        }

        /// Creates a colored dot indicating request status.
        private static func makeStatusDot(for req: RequestStore.CapturedRequest, tableView: NSTableView) -> NSView {
            let cellId = NSUserInterfaceItemIdentifier("statusDot")
            let cellView: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView,
               let dot = reused.subviews.first {
                cellView = reused
                dot.layer?.backgroundColor = statusDotColor(for: req).cgColor
            } else {
                cellView = NSTableCellView()
                cellView.identifier = cellId
                let dot = NSView()
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 5
                dot.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(dot)
                NSLayoutConstraint.activate([
                    dot.widthAnchor.constraint(equalToConstant: 10),
                    dot.heightAnchor.constraint(equalToConstant: 10),
                    dot.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
                    dot.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                ])
                dot.layer?.backgroundColor = statusDotColor(for: req).cgColor
            }
            return cellView
        }

        private static func statusDotColor(for req: RequestStore.CapturedRequest) -> NSColor {
            if req.isTunnel { return PryTheme.nsTextTertiary }
            if req.isMock { return NSColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 1) } // purple
            guard let status = req.statusCode else { return PryTheme.nsTextTertiary.withAlphaComponent(0.5) }
            switch status {
            case 200..<300: return PryTheme.nsSuccess
            case 300..<400: return PryTheme.nsWarning
            case 400..<600: return PryTheme.nsError
            default: return PryTheme.nsTextTertiary
            }
        }

        @objc func tableViewClicked(_ sender: NSTableView) {
            updateSelection(sender)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTableView else { return }
            updateSelection(tv)
        }

        private func updateSelection(_ tableView: NSTableView) {
            let row = tableView.selectedRow
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

        // MARK: - Badge colors

        static func methodColors(_ method: String) -> (NSColor, NSColor) {
            switch method.uppercased() {
            case "GET":     return (NSColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 1),     // emerald
                                   NSColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 0.18))
            case "POST":    return (NSColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 1),     // amber
                                   NSColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 0.18))
            case "PUT":     return (NSColor(red: 251/255, green: 146/255, blue: 60/255, alpha: 1),     // orange
                                   NSColor(red: 251/255, green: 146/255, blue: 60/255, alpha: 0.18))
            case "DELETE":  return (NSColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1),      // red
                                   NSColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 0.18))
            case "PATCH":   return (NSColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 1),     // violet
                                   NSColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 0.18))
            case "CONNECT": return (PryTheme.nsTextTertiary, PryTheme.nsTextTertiary.withAlphaComponent(0.10))
            default:        return (PryTheme.nsTextSecondary, NSColor.clear)
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

        static func formatDuration(_ duration: TimeInterval?) -> String {
            guard let d = duration else { return "—" }
            if d < 1 {
                return "\(Int(d * 1000))ms"
            } else {
                return String(format: "%.1fs", d)
            }
        }

        // statusColor moved to PryTheme.statusColor(_:)

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

    override func drawSelection(in dirtyRect: NSRect) {
        PryTheme.nsBgSelected.setFill()
        dirtyRect.fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovered && !isSelected {
            PryTheme.nsHover.setFill()
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
