import SwiftUI
import PryKit
import PryLib

private let maxVisibleHosts = 5

/// A group of requests from a single app, with sub-groups by host.
struct AppGroup: Identifiable, Equatable {
    let id: String // appName
    let icon: String
    let hosts: [HostEntry]
    let total: Int

    struct HostEntry: Identifiable, Equatable {
        var id: String { host }
        let host: String
        let count: Int
    }
}

@available(macOS 14, *)
@MainActor
struct SourceListView: View {
    @Environment(RequestStoreWrapper.self) private var store
    @State private var grouped: [AppGroup] = []
    /// Tracks which app groups are expanded to show all hosts (beyond maxVisibleHosts).
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        @Bindable var store = store

        if store.requests.isEmpty {
            ContentUnavailableView(
                "No Requests",
                systemImage: "antenna.radiowaves.left.and.right.slash",
                description: Text("Start the proxy and send some traffic")
                    .foregroundStyle(PryTheme.textSecondary)
            )
            .foregroundStyle(PryTheme.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PryTheme.bgMain)
        } else {
            List(selection: $store.selectedSource) {
                Label("All Traffic", systemImage: "arrow.left.arrow.right")
                    .badge(store.requests.count)
                    .tag(SourceFilter.all)

                ForEach(grouped) { group in
                    DisclosureGroup {
                        let isExpanded = expandedGroups.contains(group.id)
                        let visibleHosts = isExpanded
                            ? group.hosts
                            : Array(group.hosts.prefix(maxVisibleHosts))
                        let hiddenCount = group.hosts.count - visibleHosts.count

                        ForEach(visibleHosts) { entry in
                            Label(entry.host, systemImage: "globe")
                                .badge(entry.count)
                                .tag(SourceFilter.host(app: group.id, host: entry.host))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        if hiddenCount > 0 {
                            Button {
                                expandedGroups.insert(group.id)
                            } label: {
                                Text("\(hiddenCount) more…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        } else if isExpanded && group.hosts.count > maxVisibleHosts {
                            Button {
                                expandedGroups.remove(group.id)
                            } label: {
                                Text("Show less")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    } label: {
                        Label {
                            Text(group.id.isEmpty ? "Unknown" : group.id == "tunnel" ? "Passthrough (tunnel)" : group.id)
                                .foregroundStyle(group.id == "tunnel" ? PryTheme.textSecondary : PryTheme.textPrimary)
                        } icon: {
                            Text(group.icon)
                        }
                        .badge(group.total)
                        .tag(SourceFilter.app(group.id))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(PryTheme.bgMain)
            .onChange(of: store.requests.count) {
                recomputeGroups()
            }
            .onAppear {
                recomputeGroups()
            }
        }
    }

    private func recomputeGroups() {
        grouped = Self.computeGrouped(store.requests)
    }

    static func computeGrouped(_ requests: [RequestStore.CapturedRequest]) -> [AppGroup] {
        let byApp = Dictionary(grouping: requests, by: \.appName)
        // Sort apps alphabetically but push "tunnel" to the end
        let sortedKeys = byApp.keys.sorted { a, b in
            if a == "tunnel" { return false }
            if b == "tunnel" { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return sortedKeys.map { app in
            let reqs = byApp[app]!
            let icon: String
            if app == "tunnel" {
                icon = "🔒"
            } else {
                icon = reqs.first?.appIcon ?? "📱"
            }
            let byHost = Dictionary(grouping: reqs, by: \.host)
            let hosts = byHost.keys.sorted().map { host in
                AppGroup.HostEntry(host: host, count: byHost[host]!.count)
            }
            return AppGroup(id: app, icon: icon, hosts: hosts, total: reqs.count)
        }
    }
}
