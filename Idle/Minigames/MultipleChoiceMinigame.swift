import SwiftUI

// MARK: - MultipleChoiceMinigame

/// Child taps the correct button. Gives animated feedback then auto-advances.
struct MultipleChoiceMinigame: View {
    let choices: [MinigameChoice]
    let onComplete: (MinigameResult) -> Void

    @State private var selectedId: String? = nil
    @State private var revealed = false

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 340
            let cols = [GridItem(.flexible()), GridItem(.flexible())]

            VStack(spacing: compact ? 6 : 14) {
                LazyVGrid(columns: cols, spacing: compact ? 6 : 12) {
                    ForEach(choices) { choice in
                        choiceButton(choice, compact: compact)
                    }
                }
                if revealed {
                    continueButton(compact: compact)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: revealed)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Choice button

    @ViewBuilder
    private func choiceButton(_ choice: MinigameChoice, compact: Bool) -> some View {
        let state = buttonState(for: choice)
        Button {
            guard selectedId == nil else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedId = choice.id; revealed = true
            }
            let gen = UIImpactFeedbackGenerator(style: choice.isCorrect ? .heavy : .light)
            gen.impactOccurred()
        } label: {
            HStack(spacing: compact ? 8 : 12) {
                if let emoji = choice.emoji {
                    Text(emoji)
                        .font(.system(size: compact ? 20 : 28))
                        .frame(width: compact ? 30 : 40, height: compact ? 30 : 40)
                        .background(Circle().fill(state.badgeBackground))
                }
                Text(choice.label)
                    .font(.system(size: compact ? 13 : 16, weight: .semibold, design: .rounded))
                    .foregroundColor(state.textColor)
                    .lineLimit(2)
                Spacer()
                if revealed && selectedId == choice.id {
                    Image(systemName: choice.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: compact ? 16 : 20))
                        .foregroundColor(choice.isCorrect ? .green : .red)
                        .transition(.scale)
                }
            }
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 8 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(state.background)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(state.borderColor, lineWidth: 2))
            .scaleEffect(selectedId == choice.id ? 1.03 : 1.0)
            .animation(.spring(response: 0.25), value: selectedId)
        }
        .disabled(revealed)
    }

    // MARK: - Continue button

    private func continueButton(compact: Bool) -> some View {
        Button {
            let correct = choices.first { $0.id == selectedId }?.isCorrect ?? false
            onComplete(MinigameResult(type: .multiple_choice, completed: true,
                                      correct: correct, skipped: false, responseData: selectedId))
        } label: {
            Text("Continue →")
                .font(.system(size: compact ? 14 : 17, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 8 : 12)
                .background(Color.cyan)
                .cornerRadius(12)
        }
    }

    // MARK: - Button state helper

    struct ButtonState {
        let background: Color
        let borderColor: Color
        let textColor: Color
        let badgeBackground: Color
    }

    private func buttonState(for choice: MinigameChoice) -> ButtonState {
        guard revealed, let sid = selectedId else {
            return ButtonState(
                background: Color.white.opacity(0.1),
                borderColor: Color.white.opacity(0.2),
                textColor: .white,
                badgeBackground: Color.white.opacity(0.15)
            )
        }

        if choice.id == sid {
            // This is what the child tapped
            return choice.isCorrect
                ? ButtonState(background: Color.green.opacity(0.25), borderColor: .green,
                              textColor: .white, badgeBackground: Color.green.opacity(0.3))
                : ButtonState(background: Color.red.opacity(0.2), borderColor: .red,
                              textColor: .white, badgeBackground: Color.red.opacity(0.25))
        } else if choice.isCorrect && selectedId != nil {
            // Reveal the correct answer if child was wrong
            return ButtonState(background: Color.green.opacity(0.15), borderColor: Color.green.opacity(0.5),
                               textColor: .white.opacity(0.9), badgeBackground: Color.green.opacity(0.2))
        } else {
            return ButtonState(background: Color.white.opacity(0.05), borderColor: Color.white.opacity(0.1),
                               textColor: .white.opacity(0.4), badgeBackground: Color.white.opacity(0.08))
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        MultipleChoiceMinigame(choices: [
            MinigameChoice(id: "a", label: "Moo", emoji: "🐄", isCorrect: true),
            MinigameChoice(id: "b", label: "Woof", emoji: "🐕", isCorrect: false),
            MinigameChoice(id: "c", label: "Meow", emoji: "🐱", isCorrect: false),
            MinigameChoice(id: "d", label: "Baa", emoji: "🐑", isCorrect: false),
        ]) { result in print(result) }
        .padding()
    }
}
