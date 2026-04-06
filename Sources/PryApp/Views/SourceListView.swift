import SwiftUI
import PryKit
import PryLib

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

    var body: some View {
        @Bindable var store = store

        if store.requests.isEmpty {
            ContentUnavailableView(
                "No Requests",
                systemImage: "antenna.radiowaves.left.and.right.slash",
                description: Text("Start the proxy and send some traffic")
            )
        } else {
            List(selection: $store.selectedSource) {
                Label("All Traffic", systemImage: "arrow.left.arrow.right")
                    .badge(store.requests.count)
                    .tag(SourceFilter.all)

                ForEach(grouped) { group in
                    DisclosureGroup {
                        ForEach(group.hosts) { entry in
                            Label(entry.host, systemImage: "globe")
                                .badge(entry.count)
                                .tag(SourceFilter.host(app: group.id, host: entry.host))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } label: {
                        Label {
                            Text(group.id.isEmpty ? "Unknown" : group.id)
                        } icon: {
                            Text(group.icon)
                        }
                        .badge(group.total)
                        .tag(SourceFilter.app(group.id))
                    }
                }
            }
            .listStyle(.sidebar)
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
        return byApp.keys.sorted().map { app in
            let reqs = byApp[app]!
            let icon = reqs.first?.appIcon ?? "📱"
            let byHost = Dictionary(grouping: reqs, by: \.host)
            let hosts = byHost.keys.sorted().map { host in
                AppGroup.HostEntry(host: host, count: byHost[host]!.count)
            }
            return AppGroup(id: app, icon: icon, hosts: hosts, total: reqs.count)
        }
    }
}
