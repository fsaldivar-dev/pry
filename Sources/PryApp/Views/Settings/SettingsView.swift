import SwiftUI

@available(macOS 14, *)
@MainActor
struct SettingsView: View {
    var body: some View {
        TabView {
            DomainListView()
                .tabItem { Label("Domains", systemImage: "globe") }
            CertificateView()
                .tabItem { Label("Certificate", systemImage: "lock.shield") }
            ProxySettingsView()
                .tabItem { Label("Proxy", systemImage: "network") }
            RulesSettingsView()
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            AppearanceView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 550, height: 420)
    }
}
