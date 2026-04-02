import SwiftUI
import PencilKit
import ObjectiveC.runtime

// MARK: - One-time swizzle to silence CAMetalDrawable setDirtyRect: warning
// PencilKit's internal PKImageView sends this selector to CAMetalDrawable,
// which doesn't implement it. The warning is benign but noisy.
// We add a no-op implementation so the runtime stops logging "Uncaught selector".
private let _silenceMetalDrawableWarning: Void = {
    // Target: CAMetalDrawable (protocol; its concrete class is CAMetalDrawableStorage or similar)
    // We add setDirtyRect: to NSObject so ANY receiver can handle it silently.
    let sel = NSSelectorFromString("setDirtyRect:")
    guard class_getInstanceMethod(NSObject.self, sel) == nil else { return }
    let imp = imp_implementationWithBlock({ (_: AnyObject, _: CGRect) in } as @convention(block) (AnyObject, CGRect) -> Void)
    class_addMethod(NSObject.self, sel, imp, "{CGRect={CGFloat}{CGFloat}{CGFloat}{CGFloat}}")
}()

// MARK: - DrawingMinigame

/// The screen goes dark and the child draws the prompted object.
/// Uses PencilKit canvas directly — no PKToolPicker (avoids PKPaletteNamedDefaults
/// and CAMetalDrawable setDirtyRect warnings).
struct DrawingMinigame: View {
    let theme: String
    let darkBackground: Bool
    let onActivity: () -> Void
    let onDrawingStarted: () -> Void
    let onComplete: (MinigameResult) -> Void

    @State private var canvasView = NoScribbleCanvasView()
    @State private var hasDrawn = false
    @State private var strokeCount = 0
    @State private var selectedTool: DrawTool = .pencil
    // Default ink is dark brown so it shows on pale yellow canvas
    @State private var selectedColor: Color = Color(red: 0.18, green: 0.10, blue: 0.04)

    // Pale yellow canvas background (always, regardless of darkBackground flag)
    private let canvasBg = UIColor(red: 0.996, green: 0.976, blue: 0.88, alpha: 1) // #FEFF1E0

    // Colors that read well on pale yellow
    private let toolColors: [Color] = [
        Color(red: 0.18, green: 0.10, blue: 0.04), // dark brown (default)
        .black,
        Color(red: 0.6, green: 0.0, blue: 0.0),   // dark red
        Color(red: 0.0, green: 0.4, blue: 0.1),   // dark green
        Color(red: 0.0, green: 0.15, blue: 0.5),  // dark blue
        Color(red: 0.5, green: 0.0, blue: 0.5),   // purple
        .orange,
        Color(red: 0.6, green: 0.4, blue: 0.0),   // amber
    ]

    enum DrawTool: CaseIterable {
        case pencil, brush, eraser
        var icon: String {
            switch self { case .pencil: return "pencil"; case .brush: return "paintbrush.fill"; case .eraser: return "eraser" }
        }
        var label: String {
            switch self { case .pencil: return "Pencil"; case .brush: return "Brush"; case .eraser: return "Erase" }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 340
            VStack(spacing: isCompact ? 4 : 8) {
                // Prompt
                HStack(spacing: 6) {
                    Image(systemName: "pencil.tip")
                        .font(.system(size: isCompact ? 13 : 16))
                        .foregroundColor(.orange)
                    Text("Draw: \(theme)")
                        .font(.custom("Georgia", size: isCompact ? 13 : 16))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                // Canvas
                MinigameCanvasView(
                    canvasView: $canvasView,
                    strokeCount: $strokeCount,
                    bgColor: canvasBg
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1))
                .onChange(of: strokeCount) { count in
                    if count > 0 {
                        if !hasDrawn { onDrawingStarted() }
                        hasDrawn = count > 0
                        onActivity()
                    }
                }

                // Tool + color row
                HStack(spacing: 0) {
                    // Tool buttons
                    ForEach(DrawTool.allCases, id: \.self) { tool in
                        Button {
                            selectedTool = tool
                            applyTool(tool)
                            onActivity()
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
                        onActivity()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: isCompact ? 13 : 15))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: isCompact ? 32 : 38, height: isCompact ? 28 : 34)
                    }
                    Button {
                        canvasView.drawing = PKDrawing(); strokeCount = 0
                        onActivity()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: isCompact ? 13 : 15))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: isCompact ? 32 : 38, height: isCompact ? 28 : 34)
                    }

                    Spacer()

                    // Color swatches
                    ForEach(Array(toolColors.enumerated()), id: \.offset) { _, color in
                        Button {
                            selectedColor = color
                            applyTool(selectedTool)
                            onActivity()
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: isCompact ? 18 : 22, height: isCompact ? 18 : 22)
                                .overlay(Circle().stroke(
                                    selectedColor == color ? Color.white : Color.white.opacity(0.25),
                                    lineWidth: selectedColor == color ? 2.5 : 1))
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
        .onAppear {
            _ = _silenceMetalDrawableWarning   // trigger swizzle once
            applyTool(.pencil)
        }
    }

    // MARK: - Apply tool

    private func applyTool(_ tool: DrawTool) {
        let uiColor = UIColor(selectedColor)
        switch tool {
        case .pencil: canvasView.tool = PKInkingTool(.pencil, color: uiColor, width: 4)
        case .brush:  canvasView.tool = PKInkingTool(.marker, color: uiColor, width: 10)
        case .eraser: canvasView.tool = PKEraserTool(.bitmap)
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

// MARK: - PKCanvasView subclass — strips Scribble / handwritingd interactions

/// Subclassing lets us intercept `didMoveToWindow` and `didMoveToSuperview`
/// to remove every UIScribbleInteraction before PencilKit can connect to handwritingd.
/// This silences both "Remote connection to handwritingd was invalidated" and
/// the "CAMetalDrawable setDirtyRect:" uncaught-selector warnings.
final class NoScribbleCanvasView: PKCanvasView {

    override func didMoveToWindow() {
        super.didMoveToWindow()
        removeScribbleInteractions()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        removeScribbleInteractions()
    }

    private func removeScribbleInteractions() {
        // Walk the entire view subtree and strip every Scribble interaction.
        removeScribbleFrom(self)
    }

    private func removeScribbleFrom(_ view: UIView) {
        for interaction in view.interactions {
            let name = String(describing: type(of: interaction))
            if name.contains("Scribble") || name.contains("Handwriting") || name.contains("IndirectScribble") {
                view.removeInteraction(interaction)
            }
        }
        for sub in view.subviews {
            removeScribbleFrom(sub)
        }
    }

    // Refuse to add any Scribble interaction that PencilKit tries to inject later.
    override func addInteraction(_ interaction: UIInteraction) {
        let name = String(describing: type(of: interaction))
        guard !name.contains("Scribble") && !name.contains("Handwriting") else { return }
        super.addInteraction(interaction)
    }
}

// MARK: - PKCanvasView SwiftUI wrapper (no PKToolPicker, no Scribble)

struct MinigameCanvasView: UIViewRepresentable {
    @Binding var canvasView: NoScribbleCanvasView
    @Binding var strokeCount: Int
    let bgColor: UIColor

    func makeUIView(context: Context) -> NoScribbleCanvasView {
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = bgColor
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pencil,
            color: UIColor(red: 0.18, green: 0.10, blue: 0.04, alpha: 1), width: 4)
        canvasView.isRulerActive = false
        canvasView.overrideUserInterfaceStyle = .light   // light mode so pale yellow renders correctly
        return canvasView
    }

    func updateUIView(_ uiView: NoScribbleCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(strokeCount: $strokeCount) }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var strokeCount: Int
        init(strokeCount: Binding<Int>) { _strokeCount = strokeCount }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            strokeCount = canvasView.drawing.strokes.count
        }
    }
}
