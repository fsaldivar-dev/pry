import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
struct SourceListView: View {
    @Environment(RequestStoreWrapper.self) private var store

    /// Requests grouped by appName → host → count
    private var grouped: [(app: String, icon: String, hosts: [(host: String, count: Int)], total: Int)] {
        let byApp = Dictionary(grouping: store.requests, by: \.appName)
        return byApp.keys.sorted().map { app in
            let reqs = byApp[app]!
            let icon = reqs.first?.appIcon ?? "📱"
            let byHost = Dictionary(grouping: reqs, by: \.host)
            let hosts = byHost.keys.sorted().map { host in
                (host: host, count: byHost[host]!.count)
            }
            return (app: app, icon: icon, hosts: hosts, total: reqs.count)
        }
    }

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

                ForEach(grouped, id: \.app) { group in
                    DisclosureGroup {
                        ForEach(group.hosts, id: \.host) { entry in
                            Label(entry.host, systemImage: "globe")
                                .badge(entry.count)
                                .tag(SourceFilter.host(app: group.app, host: entry.host))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } label: {
                        Label {
                            Text(group.app.isEmpty ? "Unknown" : group.app)
                        } icon: {
                            Text(group.icon)
                        }
                        .badge(group.total)
                        .tag(SourceFilter.app(group.app))
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}
