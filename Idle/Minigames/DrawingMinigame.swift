import SwiftUI
import PencilKit

// MARK: - DrawingMinigame

/// The screen goes dark and the child draws the prompted object.
/// Uses PencilKit canvas directly — no PKToolPicker (avoids PKPaletteNamedDefaults
/// and CAMetalDrawable setDirtyRect warnings).
struct DrawingMinigame: View {
    let theme: String
    let darkBackground: Bool
    let onComplete: (MinigameResult) -> Void

    @State private var canvasView = PKCanvasView()
    @State private var hasDrawn = false
    @State private var strokeCount = 0
    @State private var selectedTool: DrawTool = .pencil
    @State private var selectedColor: Color = .white

    enum DrawTool: CaseIterable {
        case pencil, brush, eraser
        var icon: String {
            switch self { case .pencil: return "pencil"; case .brush: return "paintbrush.fill"; case .eraser: return "eraser" }
        }
        var label: String {
            switch self { case .pencil: return "Pencil"; case .brush: return "Brush"; case .eraser: return "Erase" }
        }
    }

    private let toolColors: [Color] = [.white, .yellow, .cyan, .green, .orange, .pink]

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 340
            VStack(spacing: isCompact ? 4 : 8) {
                // Prompt
                HStack(spacing: 6) {
                    Image(systemName: "pencil.tip")
                        .font(.system(size: isCompact ? 13 : 16))
                        .foregroundColor(.yellow)
                    Text("Draw: \(theme)")
                        .font(.custom("Georgia", size: isCompact ? 13 : 16))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                // Canvas — fills remaining height
                MinigameCanvasView(
                    canvasView: $canvasView,
                    strokeCount: $strokeCount,
                    darkBackground: darkBackground
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1))
                .onChange(of: strokeCount) { count in hasDrawn = count > 0 }

                // Tool + color row
                HStack(spacing: 0) {
                    // Tool buttons
                    ForEach(DrawTool.allCases, id: \.self) { tool in
                        Button {
                            selectedTool = tool
                            applyTool(tool)
                        } label: {
                            Image(systemName: tool.icon)
                                .font(.system(size: isCompact ? 13 : 15))
                                .foregroundColor(selectedTool == tool ? .yellow : .white.opacity(0.7))
                                .frame(width: isCompact ? 32 : 38, height: isCompact ? 28 : 34)
                                .background(selectedTool == tool
                                    ? Color.white.opacity(0.18)
                                    : Color.clear)
                                .cornerRadius(8)
                        }
                    }
                    // Undo / clear
                    Button {
                        canvasView.undoManager?.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: isCompact ? 13 : 15))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: isCompact ? 32 : 38, height: isCompact ? 28 : 34)
                    }
                    Button {
                        canvasView.drawing = PKDrawing(); strokeCount = 0
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: isCompact ? 13 : 15))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: isCompact ? 32 : 38, height: isCompact ? 28 : 34)
                    }

                    Spacer()

                    // Color swatches
                    ForEach(toolColors, id: \.self) { color in
                        Button {
                            selectedColor = color
                            applyTool(selectedTool)
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: isCompact ? 18 : 22, height: isCompact ? 18 : 22)
                                .overlay(Circle().stroke(Color.white.opacity(selectedColor == color ? 1 : 0.2), lineWidth: 2))
                        }
                        .padding(.horizontal, 2)
                    }

                    // Done button
                    Button { submitDrawing() } label: {
                        Text("Done")
                            .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                            .foregroundColor(hasDrawn ? .black : .white.opacity(0.35))
                            .padding(.horizontal, isCompact ? 10 : 14)
                            .padding(.vertical, isCompact ? 5 : 7)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(hasDrawn ? Color.yellow : Color.white.opacity(0.1)))
                    }
                    .disabled(!hasDrawn)
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, isCompact ? 2 : 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
            }
        }
        .onAppear { applyTool(.pencil) }
    }

    // MARK: - Apply tool

    private func applyTool(_ tool: DrawTool) {
        let uiColor = UIColor(selectedColor)
        switch tool {
        case .pencil:
            canvasView.tool = PKInkingTool(.pencil, color: uiColor, width: 4)
        case .brush:
            canvasView.tool = PKInkingTool(.marker, color: uiColor, width: 10)
        case .eraser:
            canvasView.tool = PKEraserTool(.bitmap)
        }
    }

    // MARK: - Submit

    private func submitDrawing() {
        let image = canvasView.drawing.image(from: canvasView.bounds, scale: 1.0)
        let base64 = image.pngData().map { $0.base64EncodedString() }
        onComplete(MinigameResult(type: .drawing, completed: true,
                                  correct: nil, skipped: false, responseData: base64))
    }
}

// MARK: - PKCanvasView wrapper (no PKToolPicker)

struct MinigameCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var strokeCount: Int
    let darkBackground: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = darkBackground
            ? UIColor(red: 0.03, green: 0.03, blue: 0.08, alpha: 1)
            : UIColor(red: 0.1,  green: 0.1,  blue: 0.18, alpha: 1)
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pencil, color: .white, width: 4)
        // Disable PencilKit's built-in finger drawing hint that requires PKToolPicker
        canvasView.isRulerActive = false
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
