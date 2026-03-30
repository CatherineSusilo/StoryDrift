import SwiftUI

// MARK: - MinigameOverlay

/// Full-screen overlay that wraps whichever minigame type was triggered.
struct MinigameOverlay: View {
    let trigger: MinigameTrigger
    let onComplete: (MinigameResult) -> Void

    @State private var timeRemaining: Int
    @State private var timerActive = true
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(trigger: MinigameTrigger, onComplete: @escaping (MinigameResult) -> Void) {
        // Ensure shape_sorting always has shapes before any rendering
        self.trigger = trigger.withFallbackShapes()
        self.onComplete = onComplete
        _timeRemaining = State(initialValue: trigger.timeoutSeconds ?? 30)
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop    = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            ZStack {
                // Backdrop
                backdropColor
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 0) {
                    // Header: narrator prompt + timer
                    headerBar(safeTop: safeTop)

                    // Minigame body — fills remaining space
                    Group {
                        switch trigger.type {
                        case .drawing:
                            DrawingMinigame(
                                theme: trigger.drawingTheme ?? "whatever you imagine",
                                darkBackground: trigger.drawingDarkBackground ?? true,
                                onComplete: finish
                            )
                        case .voice:
                            VoiceMinigame(
                                target: trigger.voiceTarget ?? "",
                                hint: trigger.voiceHint ?? "Say it out loud!",
                                onComplete: finish
                            )
                        case .shape_sorting:
                            ShapeSortingMinigame(
                                shapes: trigger.shapes ?? defaultShapes,
                                onComplete: finish
                            )
                        case .multiple_choice:
                            MultipleChoiceMinigame(
                                choices: trigger.choices ?? [],
                                onComplete: finish
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)

                    // Skip button
                    Button { skip() } label: {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.vertical, 10)
                    }
                    .padding(.bottom, max(safeBottom, 12))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            guard timerActive else { return }
            if timeRemaining > 0 { timeRemaining -= 1 } else { skip() }
        }
    }

    // MARK: - Sub-views

    private var backdropColor: Color {
        trigger.type == .drawing && (trigger.drawingDarkBackground ?? true)
            ? Color.black.opacity(0.92)
            : Color.black.opacity(0.78)
    }

    private func headerBar(safeTop: CGFloat) -> some View {
        HStack(spacing: 16) {
            // Narrator prompt
            Text(trigger.narratorPrompt)
                .font(.custom("Georgia", size: 17))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Countdown ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 3)
                    .frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: CGFloat(timeRemaining) / CGFloat(trigger.timeoutSeconds ?? 30))
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timeRemaining)
                Text("\(timeRemaining)")
                    .font(.system(size: 13, weight: .bold))
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
