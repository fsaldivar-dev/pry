import SwiftUI

@available(macOS 14, *)
struct BackgroundView: View {
    var body: some View {
        ZStack {
            // Base dark background
            Color(red: 5/255, green: 5/255, blue: 7/255) // #050507 near-black

            // Blue orb — top left
            Circle()
                .fill(RadialGradient(
                    colors: [Color.blue.opacity(0.15), Color.clear],
                    center: .center, startRadius: 0, endRadius: 300))
                .frame(width: 700, height: 700)
                .offset(x: -250, y: -200)
                .blur(radius: 120)

            // Cyan orb — bottom right
            Circle()
                .fill(RadialGradient(
                    colors: [Color.cyan.opacity(0.12), Color.clear],
                    center: .center, startRadius: 0, endRadius: 250))
                .frame(width: 500, height: 500)
                .offset(x: 300, y: 200)
                .blur(radius: 100)
        }
        .ignoresSafeArea()
        .drawingGroup() // Flatten to texture for performance
    }
}
