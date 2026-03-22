import SwiftUI
import PencilKit

struct InteractiveElementsView: View {
    let element: InteractiveElement
    let onComplete: (String) -> Void
    
    var body: some View {
        switch element.type {
        case .choice:
            ChoiceView(element: element, onComplete: onComplete)
        case .drawing:
            DrawingView(element: element, onComplete: onComplete)
        case .quiz:
            QuizView(element: element, onComplete: onComplete)
        }
    }
}

// MARK: - Choice View

struct ChoiceView: View {
    let element: InteractiveElement
    let onComplete: (String) -> Void
    @State private var selectedOption: String?
    
    var body: some View {
        VStack(spacing: 24) {
            // Question
            VStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(element.content)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding()
            
            // Options
            VStack(spacing: 12) {
                ForEach(element.options ?? [], id: \.self) { option in
                    Button(action: {
                        selectedOption = option
                        // Allow time for selection animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onComplete(option)
                        }
                    }) {
                        HStack {
                            Text(option)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            if selectedOption == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 24))
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedOption == option ? Color.purple.opacity(0.3) : Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(selectedOption == option ? Color.purple : Color.white.opacity(0.1), lineWidth: 2)
                                )
                        )
                    }
                    .disabled(selectedOption != nil)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.4))
        )
        .padding()
    }
}

// MARK: - Drawing View

struct DrawingView: View {
    let element: InteractiveElement
    let onComplete: (String) -> Void
    
    @State private var canvasView = PKCanvasView()
    @State private var isDrawing = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Prompt
            VStack(spacing: 12) {
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(element.content)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding()
            
            // Canvas
            DrawingCanvasView(canvasView: $canvasView)
                .frame(height: 300)
                .background(Color.white)
                .cornerRadius(20)
                .padding(.horizontal)
            
            // Tools
            HStack(spacing: 16) {
                Button(action: {
                    canvasView.drawing = PKDrawing()
                }) {
                    Label("Clear", systemImage: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(12)
                }
                
                Spacer()
                
                Button(action: {
                    // Save drawing as base64
                    let image = canvasView.drawing.image(from: canvasView.bounds, scale: 1.0)
                    if let data = image.pngData() {
                        let base64 = data.base64EncodedString()
                        onComplete(base64)
                    }
                }) {
                    Label("Done", systemImage: "checkmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.4))
        )
        .padding()
    }
}

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .white
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

// MARK: - Quiz View

struct QuizView: View {
    let element: InteractiveElement
    let onComplete: (String) -> Void
    
    @State private var selectedAnswer: String?
    @State private var showingResult = false
    
    private var correctAnswer: String? {
        element.options?.first
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Question
            VStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(element.content)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding()
            
            // Options
            VStack(spacing: 12) {
                ForEach(element.options ?? [], id: \.self) { option in
                    Button(action: {
                        selectedAnswer = option
                        showingResult = true
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            onComplete(option)
                        }
                    }) {
                        HStack {
                            Text(option)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            if showingResult && selectedAnswer == option {
                                Image(systemName: option == correctAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(option == correctAnswer ? .green : .red)
                                    .font(.system(size: 24))
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(backgroundColor(for: option))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(borderColor(for: option), lineWidth: 2)
                                )
                        )
                    }
                    .disabled(showingResult)
                }
            }
            .padding(.horizontal)
            
            // Result message
            if showingResult {
                Text(selectedAnswer == correctAnswer ? "Correct! Well done! 🎉" : "Not quite, but good try! 💫")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(selectedAnswer == correctAnswer ? .green : .orange)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.4))
        )
        .padding()
        .animation(.spring(), value: showingResult)
    }
    
    private func backgroundColor(for option: String) -> Color {
        if !showingResult {
            return Color.white.opacity(0.05)
        }
        
        if selectedAnswer == option {
            return option == correctAnswer ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
        }
        
        return Color.white.opacity(0.05)
    }
    
    private func borderColor(for option: String) -> Color {
        if !showingResult {
            return Color.white.opacity(0.1)
        }
        
        if selectedAnswer == option {
            return option == correctAnswer ? .green : .red
        }
        
        return Color.white.opacity(0.1)
    }
}

#Preview {
    VStack(spacing: 40) {
        InteractiveElementsView(
            element: InteractiveElement(
                id: "1",
                type: .choice,
                content: "Which path should we take?",
                options: ["The forest trail", "The mountain path", "The river crossing"],
                paragraphIndex: 0,
                completed: false,
                response: nil
            ),
            onComplete: { _ in }
        )
        
        InteractiveElementsView(
            element: InteractiveElement(
                id: "2",
                type: .quiz,
                content: "What color is the sky?",
                options: ["Blue", "Green", "Red"],
                paragraphIndex: 1,
                completed: false,
                response: nil
            ),
            onComplete: { _ in }
        )
    }
    .background(
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.15, green: 0.05, blue: 0.25)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    )
}
