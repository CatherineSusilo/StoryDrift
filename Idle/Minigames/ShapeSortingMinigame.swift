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
        GeometryReader { geo in
            let compact = geo.size.height < 340
            let slotSize: CGFloat  = compact ? 60 : 90
            let shapeSize: CGFloat = compact ? 44 : 64

            VStack(spacing: compact ? 6 : 16) {
                Text("Sort the shapes!")
                    .font(.custom("Georgia", size: compact ? 14 : 18))
                    .foregroundColor(.white)

                // Drop zone slots
                HStack(spacing: compact ? 10 : 16) {
                    ForEach(shapes, id: \.id) { shape in
                        dropSlot(for: shape, slotSize: slotSize, shapeSize: shapeSize)
                    }
                }

                Divider().background(Color.white.opacity(0.2))

                // Shape tray
                HStack(spacing: compact ? 14 : 20) {
                    ForEach(shapes, id: \.id) { shape in
                        if placements[shape.id] == nil {
                            draggableShape(shape, size: shapeSize)
                        } else {
                            shapeView(shape, opacity: 0.15)
                                .frame(width: shapeSize, height: shapeSize)
                        }
                    }
                }

                if allPlaced {
                    Button {
                        celebrating = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            onComplete(MinigameResult(type: .shape_sorting, completed: true,
                                                      correct: true, skipped: false, responseData: nil))
                        }
                    } label: {
                        Text("Great job! Continue 🎉")
                            .font(.system(size: compact ? 14 : 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, compact ? 8 : 12)
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: allPlaced)
        }
    }

    // MARK: - Drop slot

    @ViewBuilder
    private func dropSlot(for shape: ShapeSlot, slotSize: CGFloat, shapeSize: CGFloat) -> some View {
        let placedShape = shapes.first { placements[$0.id] == shape.targetSlotId }

        ZStack {
            shapeOutline(shape)
                .foregroundColor(colorFromHex(shape.color).opacity(0.3))
                .frame(width: slotSize, height: slotSize)
                .overlay(
                    shapeOutline(shape)
                        .stroke(colorFromHex(shape.color).opacity(0.7), lineWidth: 2.5)
                        .frame(width: slotSize, height: slotSize)
                )
            if let placed = placedShape {
                shapeView(placed, opacity: 1.0)
                    .frame(width: shapeSize * 0.75, height: shapeSize * 0.75)
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
    private func draggableShape(_ shape: ShapeSlot, size: CGFloat) -> some View {
        shapeView(shape, opacity: 1.0)
            .frame(width: size, height: size)
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
