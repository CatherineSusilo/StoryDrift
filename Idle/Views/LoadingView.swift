import SwiftUI

struct LoadingView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("🌙")
                    .font(.system(size: 64))
                    .rotationEffect(.degrees(isAnimating ? 15 : -15))
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: isAnimating
                    )

                Text("loading…")
                    .font(Theme.bodyFont(size: 20))
                    .foregroundColor(Theme.inkMuted)
            }
        }
        .onAppear { isAnimating = true }
    }
}

#Preview {
    LoadingView()
}
