import SwiftUI

@available(macOS 14, *)
struct ContentView: View {
    var body: some View {
        MainWindow()
            .frame(minWidth: 900, minHeight: 600)
            .tint(PryTheme.accent)
            .preferredColorScheme(.dark)
            .background(PryTheme.bgMain)
    }
}
