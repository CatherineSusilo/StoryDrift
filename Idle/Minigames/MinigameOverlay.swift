import SwiftUI

// MARK: - MinigameOverlay

/// Full-screen overlay that wraps whichever minigame type was triggered.
struct MinigameOverlay: View {
    let trigger: MinigameTrigger
    let onComplete: (MinigameResult) -> Void

    // Inactivity timer: auto-closes after 60 s of no interaction.
    // Resets to 60 whenever the child taps/draws anything.
    private let inactivityLimit = 60
    @State private var inactivityRemaining: Int = 60

    // For drawing only: while the child has started drawing, we pause
    // the inactivity timer so the story doesn't close mid-stroke.
    @State private var childIsDrawing = false

    @State private var timerActive = true
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(trigger: MinigameTrigger, onComplete: @escaping (MinigameResult) -> Void) {
        self.trigger = trigger.withFallbackShapes()
        self.onComplete = onComplete
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop    = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            ZStack {
                backdropColor
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 0) {
                    headerBar(safeTop: safeTop)

                    Group {
                        switch trigger.type {
                        case .drawing:
                            DrawingMinigame(
                                theme: trigger.drawingTheme ?? "whatever you imagine",
                                darkBackground: trigger.drawingDarkBackground ?? true,
                                onActivity: handleActivity,
                                onDrawingStarted: { childIsDrawing = true },
                                onComplete: finish
                            )
                        case .voice:
                            VoiceMinigame(
                                target: trigger.voiceTarget ?? "",
                                hint: trigger.voiceHint ?? "Say it out loud!",
                                onActivity: handleActivity,
                                onComplete: finish
                            )
                        case .shape_sorting:
                            ShapeSortingMinigame(
                                shapes: trigger.shapes ?? defaultShapes,
                                onActivity: handleActivity,
                                onComplete: finish
                            )
                        case .multiple_choice:
                            MultipleChoiceMinigame(
                                choices: trigger.choices ?? [],
                                onActivity: handleActivity,
                                onComplete: finish
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)

                    Button { skip() } label: {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.vertical, 10)
                    }
                    .simultaneousGesture(TapGesture().onEnded { handleActivity() })
                    .padding(.bottom, max(safeBottom, 12))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .onReceive(ticker) { _ in
            guard timerActive else { return }
            // While the child is actively drawing, hold the inactivity clock.
            if childIsDrawing { return }
            if inactivityRemaining > 0 {
                inactivityRemaining -= 1
            } else {
                skip()
            }
        }
    }

    // MARK: - Activity callback (called by every sub-minigame on any interaction)

    private func handleActivity() {
        inactivityRemaining = inactivityLimit
    }

    // MARK: - Sub-views

    private var backdropColor: Color {
        trigger.type == .drawing && (trigger.drawingDarkBackground ?? true)
            ? Color.black.opacity(0.92)
            : Color.black.opacity(0.78)
    }

    private func headerBar(safeTop: CGFloat) -> some View {
        HStack(spacing: 16) {
            Text(trigger.narratorPrompt)
                .font(.custom("Georgia", size: 17))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Inactivity countdown ring — shows remaining idle time
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 3)
                    .frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: childIsDrawing ? 1.0 : CGFloat(inactivityRemaining) / CGFloat(inactivityLimit))
                    .stroke(childIsDrawing ? Color.green : Color.cyan,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: inactivityRemaining)
                Image(systemName: childIsDrawing ? "pencil" : "timer")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.top, max(safeTop, 12))
        .padding(.bottom, 12)
    }

    // MARK: - Actions

    private func finish(_ result: MinigameResult) {
        timerActive = false
        onComplete(result)
    }

    private func skip() {
        timerActive = false
        onComplete(MinigameResult(type: trigger.type, completed: false,
                                  correct: nil, skipped: true, responseData: nil))
    }

    private var defaultShapes: [ShapeSlot] {
        [
            ShapeSlot(id: "s1", shape: "circle",   color: "#FF6B6B", targetSlotId: "slot_circle"),
            ShapeSlot(id: "s2", shape: "square",   color: "#4ECDC4", targetSlotId: "slot_square"),
            ShapeSlot(id: "s3", shape: "triangle", color: "#45B7D1", targetSlotId: "slot_triangle"),
        ]
    }
}
