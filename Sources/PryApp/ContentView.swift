import SwiftUI

@available(macOS 14, *)
struct ContentView: View {
    var body: some View {
        MainWindow()
            .frame(minWidth: 900, minHeight: 600)
            .tint(PryTheme.accent)
            .preferredColorScheme(.dark)
            .background(PryTheme.bgMain.ignoresSafeArea())
            .onAppear {
                // Belt-and-suspenders: force NSWindow bg color
                DispatchQueue.main.async {
                    for window in NSApplication.shared.windows {
                        window.backgroundColor = PryTheme.nsBgMain
                    }
                }
            }
    }
}
