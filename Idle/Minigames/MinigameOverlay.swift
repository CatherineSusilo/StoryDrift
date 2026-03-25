import SwiftUI

// MARK: - Minigame Data Models

enum MinigameType: String, Codable {
    case drawing, voice, shape_sorting, multiple_choice
}

struct MinigameChoice: Codable, Identifiable {
    let id: String
    let label: String
    let emoji: String?
    let isCorrect: Bool
}

struct ShapeSlot: Codable, Identifiable {
    let id: String
    let shape: String      // circle | square | triangle | star | heart
    let color: String      // hex
    let targetSlotId: String
}

struct MinigameTrigger: Codable {
    let type: MinigameType
    let narratorPrompt: String
    let drawingTheme: String?
    let drawingDarkBackground: Bool?
    let voiceTarget: String?
    let voiceHint: String?
    let choices: [MinigameChoice]?
    let shapes: [ShapeSlot]?
    let timeoutSeconds: Int?
}

struct MinigameResult {
    let type: MinigameType
    let completed: Bool
    let correct: Bool?
    let skipped: Bool
    let responseData: String?   // base64 image / transcribed word / choice id
}

// MARK: - MinigameOverlay

/// Full-screen overlay that wraps whichever minigame type was triggered.
struct MinigameOverlay: View {
    let trigger: MinigameTrigger
    let onComplete: (MinigameResult) -> Void

    @State private var timeRemaining: Int
    @State private var timerActive = true
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(trigger: MinigameTrigger, onComplete: @escaping (MinigameResult) -> Void) {
        self.trigger = trigger
        self.onComplete = onComplete
        _timeRemaining = State(initialValue: trigger.timeoutSeconds ?? 30)
    }

    var body: some View {
        ZStack {
            // Backdrop — dark for drawing, semi-translucent for others
            backdropColor
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 0) {
                // Header: narrator prompt + timer
                headerBar

                // Minigame body
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
                .padding(.horizontal, 20)

                // Skip button
                Button {
                    skip()
                } label: {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.vertical, 12)
                }
                .padding(.bottom, 16)
            }
        }
        .onReceive(timer) { _ in
            guard timerActive else { return }
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                skip()
            }
        }
    }

    // MARK: - Sub-views

    private var backdropColor: Color {
        trigger.type == .drawing && (trigger.drawingDarkBackground ?? true)
            ? Color.black.opacity(0.92)
            : Color.black.opacity(0.78)
    }

    private var headerBar: some View {
        VStack(spacing: 8) {
            // Narrator prompt pill
            Text(trigger.narratorPrompt)
                .font(.custom("Georgia", size: 20))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                )
                .padding(.top, 60)

            // Countdown ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 3)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: CGFloat(timeRemaining) / CGFloat(trigger.timeoutSeconds ?? 30))
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timeRemaining)
                Text("\(timeRemaining)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.top, 6)
        }
        .padding(.bottom, 20)
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
