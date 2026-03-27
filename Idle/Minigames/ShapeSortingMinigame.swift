import SwiftUI

// MARK: - ShapeSortingMinigame

/// Child drags coloured shapes to their matching outlines.
struct ShapeSortingMinigame: View {
    let shapes: [ShapeSlot]
    let onComplete: (MinigameResult) -> Void

    // Maps shapeId → its current slotId (nil = still in tray)
    @State private var placements: [String: String] = [:]
    @State private var dragging: String? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var dragPosition: CGPoint = .zero
    @State private var celebrating = false

    private var allPlaced: Bool {
        shapes.allSatisfy { s in placements[s.id] == s.targetSlotId }
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Sort the shapes!")
                .font(.custom("Georgia", size: 18))
                .foregroundColor(.white)

            // Drop zone slots
            HStack(spacing: 16) {
                ForEach(shapes, id: \.id) { shape in
                    dropSlot(for: shape)
                }
            }
            .frame(height: 120)

            Divider()
                .background(Color.white.opacity(0.2))

            // Shape tray — unplaced shapes
            HStack(spacing: 20) {
                ForEach(shapes, id: \.id) { shape in
                    if placements[shape.id] == nil {
                        draggableShape(shape)
                    } else {
                        // Placeholder so tray keeps its size
                        shapeView(shape, opacity: 0.15)
                            .frame(width: 64, height: 64)
                    }
                }
            }
            .frame(height: 100)

            if allPlaced {
                Button {
                    celebrating = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        onComplete(MinigameResult(type: .shape_sorting, completed: true,
                                                  correct: true, skipped: false, responseData: nil))
                    }
                } label: {
                    Text("Great job! Continue 🎉")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .cornerRadius(14)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: allPlaced)
    }

    // MARK: - Drop slot

    @ViewBuilder
    private func dropSlot(for shape: ShapeSlot) -> some View {
        let isOccupied = placements.values.contains(shape.targetSlotId)
        let placedShape = shapes.first { placements[$0.id] == shape.targetSlotId }

        ZStack {
            // Outline
            shapeOutline(shape)
                .foregroundColor(colorFromHex(shape.color).opacity(0.3))
                .frame(width: 90, height: 90)
                .overlay(
                    shapeOutline(shape)
                        .stroke(colorFromHex(shape.color).opacity(0.7), lineWidth: 2.5)
                        .frame(width: 90, height: 90)
                )

            if let placed = placedShape {
                shapeView(placed, opacity: 1.0)
                    .frame(width: 60, height: 60)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onDrop(of: ["public.text"], isTargeted: nil) { providers in
            providers.first?.loadObject(ofClass: NSString.self) { item, _ in
                if let id = item as? String {
                    DispatchQueue.main.async {
                        handleDrop(shapeId: id, onto: shape.targetSlotId, expectedSlot: shape.targetSlotId)
                    }
                }
            }
            return true
        }
    }

    // MARK: - Draggable shape

    @ViewBuilder
    private func draggableShape(_ shape: ShapeSlot) -> some View {
        shapeView(shape, opacity: 1.0)
            .frame(width: 64, height: 64)
            .scaleEffect(dragging == shape.id ? 1.15 : 1.0)
            .shadow(color: colorFromHex(shape.color).opacity(0.5), radius: dragging == shape.id ? 12 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
            .onDrag {
                dragging = shape.id
                return NSItemProvider(object: shape.id as NSString)
            }
    }

    // MARK: - Drop handling

    private func handleDrop(shapeId: String, onto slotId: String, expectedSlot: String) {
        guard let shape = shapes.first(where: { $0.id == shapeId }) else { return }
        if slotId == shape.targetSlotId {
            withAnimation(.spring()) {
                placements[shapeId] = slotId
            }
        }
        dragging = nil
    }

    // MARK: - Shape drawing helpers

    @ViewBuilder
    private func shapeView(_ shape: ShapeSlot, opacity: Double) -> some View {
        shapeOutline(shape)
            .fill(colorFromHex(shape.color).opacity(opacity))
    }

    private func shapeOutline(_ shape: ShapeSlot) -> AnyShape {
        switch shape.shape {
        case "circle":   return AnyShape(Circle())
        case "square":   return AnyShape(RoundedRectangle(cornerRadius: 6))
        case "triangle": return AnyShape(Triangle())
        case "star":     return AnyShape(Star(points: 5, innerRatio: 0.45))
        default:         return AnyShape(Heart())
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return .white }
        return Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double(value         & 0xFF) / 255
        )
    }
}

// MARK: - Custom shapes

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

struct Star: Shape {
    var points: Int = 5
    var innerRatio: CGFloat = 0.45

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRatio
        let count  = points * 2
        return Path { p in
            for i in 0..<count {
                let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
                let r = i.isMultiple(of: 2) ? outerR : innerR
                let pt = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        }
    }
}

struct Heart: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            let w = rect.width, h = rect.height
            p.move(to: CGPoint(x: w / 2, y: h * 0.85))
            p.addCurve(to: CGPoint(x: 0, y: h * 0.3),
                       control1: CGPoint(x: w * 0.1, y: h * 0.9),
                       control2: CGPoint(x: 0, y: h * 0.55))
            p.addArc(center: CGPoint(x: w * 0.25, y: h * 0.3),
                     radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addArc(center: CGPoint(x: w * 0.75, y: h * 0.3),
                     radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addCurve(to: CGPoint(x: w / 2, y: h * 0.85),
                       control1: CGPoint(x: w, y: h * 0.55),
                       control2: CGPoint(x: w * 0.9, y: h * 0.9))
        }
    }
}

// Type-eraser for Shape protocol
struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { _path = shape.path(in:) }
    func path(in rect: CGRect) -> Path { _path(rect) }
}
