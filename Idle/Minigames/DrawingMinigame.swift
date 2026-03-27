import SwiftUI
import PencilKit

// MARK: - DrawingMinigame

/// The screen goes dark and the child draws the prompted object.
/// Uses PencilKit for smooth, natural drawing. Saves as base64 PNG.
struct DrawingMinigame: View {
    let theme: String
    let darkBackground: Bool
    let onComplete: (MinigameResult) -> Void

    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var hasDrawn = false
    @State private var strokeCount = 0

    var body: some View {
        VStack(spacing: 20) {
            // Prompt label
            HStack(spacing: 10) {
                Image(systemName: "pencil.tip")
                    .font(.system(size: 18))
                    .foregroundColor(.yellow)
                Text("Draw \(theme)")
                    .font(.custom("Georgia", size: 18))
                    .foregroundColor(.white)
            }

            // Canvas
            MinigameCanvasView(
                canvasView: $canvasView,
                toolPicker: $toolPicker,
                strokeCount: $strokeCount,
                darkBackground: darkBackground
            )
            .frame(height: 320)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
            )
            .onChange(of: strokeCount) { count in
                hasDrawn = count > 0
            }

            // Tool row
            toolRow

            // Done button — only enabled after at least one stroke
            Button {
                submitDrawing()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("I'm done!")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 17))
                .foregroundColor(hasDrawn ? .black : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(hasDrawn ? Color.yellow : Color.white.opacity(0.1))
                )
            }
            .disabled(!hasDrawn)
            .animation(.easeInOut(duration: 0.2), value: hasDrawn)
        }
    }

    // MARK: - Tool row

    private var toolRow: some View {
        HStack(spacing: 16) {
            toolButton(icon: "pencil", label: "Pencil") {
                let ink = PKInkingTool(.pencil, color: .white, width: 5)
                canvasView.tool = ink
            }
            toolButton(icon: "paintbrush.fill", label: "Brush") {
                let ink = PKInkingTool(.marker, color: .cyan, width: 12)
                canvasView.tool = ink
            }
            toolButton(icon: "eraser", label: "Erase") {
                canvasView.tool = PKEraserTool(.bitmap)
            }
            toolButton(icon: "arrow.uturn.backward", label: "Undo") {
                canvasView.undoManager?.undo()
            }
            toolButton(icon: "trash", label: "Clear") {
                canvasView.drawing = PKDrawing()
                strokeCount = 0
            }
        }
    }

    private func toolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.85))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
        }
    }

    // MARK: - Submit

    private func submitDrawing() {
        // Render canvas to PNG → base64
        let image = canvasView.drawing.image(from: canvasView.bounds, scale: 1.0)
        let base64 = image.pngData().map { $0.base64EncodedString() }

        onComplete(MinigameResult(
            type: .drawing,
            completed: true,
            correct: nil,           // drawing has no wrong answer
            skipped: false,
            responseData: base64
        ))
    }
}

// MARK: - PKCanvasView SwiftUI wrapper

struct MinigameCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var toolPicker: PKToolPicker
    @Binding var strokeCount: Int
    let darkBackground: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = darkBackground
            ? UIColor(red: 0.03, green: 0.03, blue: 0.08, alpha: 1)
            : UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1)
        canvasView.drawingPolicy = .anyInput

        // Default tool: white pencil
        canvasView.tool = PKInkingTool(.pencil, color: .white, width: 5)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(strokeCount: $strokeCount) }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var strokeCount: Int
        init(strokeCount: Binding<Int>) { _strokeCount = strokeCount }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            strokeCount = canvasView.drawing.strokes.count
        }
    }
}
