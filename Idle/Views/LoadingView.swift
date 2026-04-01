import SwiftUI

struct LoadingView: View {
    @State private var isAnimating = false
    @State private var messageIndex = 0

    private let messages = [
        "writing your story…",
        "painting the first scene…",
        "almost ready…",
    ]

    // Timer to cycle through messages
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

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

                Text(messages[messageIndex])
                    .font(Theme.bodyFont(size: 20))
                    .foregroundColor(Theme.inkMuted)
                    .transition(.opacity)
                    .id(messageIndex)
                    .animation(.easeInOut(duration: 0.4), value: messageIndex)
            }
        }
        .onAppear { isAnimating = true }
        .onReceive(timer) { _ in
            withAnimation {
                messageIndex = (messageIndex + 1) % messages.count
            }
        }
    }
}

#Preview {
    LoadingView()
}
