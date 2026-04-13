import SwiftUI

extension View {
    /// Glass material on macOS 26+, falls back to `.bar` on older systems.
    @ViewBuilder
    func pryBarBackground() -> some View {
        if #available(macOS 26, *) {
            self.background(.clear)
                .glassEffect(.regular)
        } else {
            self.background(.bar)
        }
    }
}
