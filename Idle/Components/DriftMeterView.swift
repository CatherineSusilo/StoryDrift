import SwiftUI

struct DriftMeterView: View {
    let driftScore: Double
    let isCompact: Bool

    // Sanitized value — clamps to 0–100 and replaces NaN/Inf
    private var safeDrift: Double {
        let v = driftScore.isFinite ? driftScore : 0
        return min(max(v, 0), 100)
    }

    init(driftScore: Double, isCompact: Bool = false) {
        self.driftScore = driftScore
        self.isCompact = isCompact
    }

    private var driftColor: Color {
        switch safeDrift {
        case 0..<25:
            return .red
        case 25..<50:
            return .orange
        case 50..<75:
            return .yellow
        case 75..<90:
            return .green
        default:
            return .cyan
        }
    }

    private var driftStatus: String {
        switch safeDrift {
        case 0..<25:
            return "Wide Awake"
        case 25..<50:
            return "Relaxing"
        case 50..<75:
            return "Drowsy"
        case 75..<90:
            return "Nearly Asleep"
        default:
            return "Asleep"
        }
    }

    var body: some View {
        if isCompact {
            compactView
        } else {
            fullView
        }
    }

    private var compactView: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(driftColor)

                    Text("Drift Score")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                Text("\(Int(safeDrift))%")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(driftColor)
            }

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 12)

                // Progress
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [driftColor.opacity(0.8), driftColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * (safeDrift / 100), height: 12)
                }
                .frame(height: 12)
            }

            Text(driftStatus)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.3))
        )
    }

    private var fullView: some View {
        VStack(spacing: 24) {
            // Header
            Text("Drift Score")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            // Circular Progress
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 20)
                    .frame(width: 200, height: 200)

                // Progress circle
                Circle()
                    .trim(from: 0, to: safeDrift / 100)
                    .stroke(
                        LinearGradient(
                            colors: [driftColor.opacity(0.6), driftColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1), value: safeDrift)

                // Center content
                VStack(spacing: 8) {
                    Text("\(Int(safeDrift))%")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(driftColor)

                    Text(driftStatus)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            // Status indicators
            VStack(spacing: 16) {
                DriftIndicator(
                    label: "0-25%",
                    status: "Wide Awake",
                    color: .red,
                    isActive: safeDrift < 25
                )

                DriftIndicator(
                    label: "25-50%",
                    status: "Relaxing",
                    color: .orange,
                    isActive: safeDrift >= 25 && safeDrift < 50
                )

                DriftIndicator(
                    label: "50-75%",
                    status: "Drowsy",
                    color: .yellow,
                    isActive: safeDrift >= 50 && safeDrift < 75
                )

                DriftIndicator(
                    label: "75-90%",
                    status: "Nearly Asleep",
                    color: .green,
                    isActive: safeDrift >= 75 && safeDrift < 90
                )

                DriftIndicator(
                    label: "90-100%",
                    status: "Asleep",
                    color: .cyan,
                    isActive: safeDrift >= 90
                )
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

struct DriftIndicator: View {
    let label: String
    let status: String
    let color: Color
    let isActive: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(isActive ? color : Color.white.opacity(0.1))
                .frame(width: 16, height: 16)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 60, alignment: .leading)

            Text(status)
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : .white.opacity(0.4))

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? color.opacity(0.15) : Color.clear)
        )
    }
}

#Preview {
    VStack(spacing: 40) {
        DriftMeterView(driftScore: 65, isCompact: true)
            .padding()

        DriftMeterView(driftScore: 65, isCompact: false)
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
