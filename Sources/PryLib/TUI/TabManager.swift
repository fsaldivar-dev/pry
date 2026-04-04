import Foundation

public struct Tab {
    public let name: String
    public let filter: String?
}

public class TabManager {
    public var tabs: [Tab]
    public var activeTabIndex: Int = 0

    public init() {
        tabs = [Tab(name: "All", filter: nil)]
    }

    public func addTab(name: String, filter: String?) {
        tabs.append(Tab(name: name, filter: filter))
    }

    public func filteredRequests(from store: RequestStore) -> [RequestStore.CapturedRequest] {
        let all = store.getAll()
        guard activeTabIndex < tabs.count else { return all }
        let tab = tabs[activeTabIndex]
        guard let filter = tab.filter else { return all }
        let lower = filter.lowercased()
        return all.filter { req in
            req.host.lowercased().contains(lower) ||
            req.url.lowercased().contains(lower)
        }
    }
}
