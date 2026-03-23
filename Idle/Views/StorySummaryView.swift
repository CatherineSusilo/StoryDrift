import SwiftUI
import Charts

struct StorySummaryView: View {
    let story: Story
    let driftHistory: [Double]
    let duration: TimeInterval
    let onDismiss: () -> Void

    private var chartData: [ChartDataPoint] {
        driftHistory.enumerated().map { ChartDataPoint(time: $0.offset, score: $0.element) }
    }

    private var sleepOnsetTime: String {
        guard let t = story.sleepOnsetTime else { return "N/A" }
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: t)
    }

    private var formattedDuration: String {
        let m = Int(duration / 60), s = Int(duration.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {

                    // ── Hero ──
                    VStack(spacing: 10) {
                        Text("🌙")
                            .font(.system(size: 60))
                        Text("sweet dreams!")
                            .font(Theme.titleFont(size: 36))
                            .foregroundColor(Theme.ink)
                        Text("story complete")
                            .font(Theme.bodyFont(size: 18))
                            .foregroundColor(Theme.inkMuted)
                    }
                    .padding(.top, 40)

                    // ── Story title & themes ──
                    VStack(spacing: 12) {
                        Text(story.title)
                            .font(Theme.titleFont(size: 24))
                            .foregroundColor(Theme.ink)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 8) {
                            ForEach(story.themes, id: \.self) { theme in
                                Text(theme)
                                    .font(Theme.bodyFont(size: 13))
                                    .foregroundColor(Theme.ink.opacity(0.75))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.accent.opacity(0.3))
                                    .cornerRadius(Theme.radiusSM)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // ── Stats grid ──
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatCard(icon: "timer",                    value: formattedDuration, label: "duration")
                        StatCard(icon: "moon.zzz.fill",            value: sleepOnsetTime,    label: "sleep time")
                        StatCard(icon: "book.fill",                value: "\(story.paragraphs.count)", label: "paragraphs")
                        StatCard(icon: "chart.line.uptrend.xyaxis", value: "\(Int(driftHistory.last ?? 0))%", label: "final drift")
                    }
                    .padding(.horizontal, 20)

                    // ── Drift chart ──
                    VStack(alignment: .leading, spacing: 12) {
                        Text("drift progress")
                            .font(Theme.titleFont(size: 20))
                            .foregroundColor(Theme.ink)

                        if #available(iOS 16.0, *) {
                            Chart(chartData) { point in
                                LineMark(
                                    x: .value("Time", point.time),
                                    y: .value("Drift", point.score)
                                )
                                .foregroundStyle(Theme.ink)
                                .interpolationMethod(.catmullRom)

                                AreaMark(
                                    x: .value("Time", point.time),
                                    y: .value("Drift", point.score)
                                )
                                .foregroundStyle(Theme.ink.opacity(0.08))
                                .interpolationMethod(.catmullRom)
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis {
                                AxisMarks(position: .leading) { _ in
                                    AxisValueLabel()
                                        .foregroundStyle(Theme.inkMuted)
                                }
                            }
                            .frame(height: 180)
                        } else {
                            SimpleDriftChart(data: chartData).frame(height: 180)
                        }
                    }
                    .padding(18)
                    .parchmentCard(cornerRadius: Theme.radiusMD)
                    .padding(.horizontal, 20)

                    // ── Actions ──
                    VStack(spacing: 12) {
                        Button(action: onDismiss) {
                            Text("back to dashboard")
                                .font(Theme.bodyFont(size: 18))
                                .fontWeight(.bold)
                                .foregroundColor(Theme.card)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Theme.ink)
                                .cornerRadius(Theme.radiusMD)
                                .shadow(color: Theme.ink.opacity(0.2), radius: 5, x: 0, y: 3)
                        }

                        Button(action: {}) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("share summary")
                            }
                            .font(Theme.bodyFont(size: 16))
                            .foregroundColor(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.card)
                            .cornerRadius(Theme.radiusMD)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMD).stroke(Theme.border, lineWidth: 1.5))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - StatCard
struct StatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Theme.inkMuted)
            Text(value)
                .font(Theme.titleFont(size: 26))
                .foregroundColor(Theme.ink)
            Text(label)
                .font(Theme.bodyFont(size: 13))
                .foregroundColor(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .parchmentCard(cornerRadius: Theme.radiusMD)
    }
}

// MARK: - ChartDataPoint
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let time: Int
    let score: Double
}

// MARK: - SimpleDriftChart (iOS 15 fallback)
struct SimpleDriftChart: View {
    let data: [ChartDataPoint]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !data.isEmpty else { return }
                let maxValue = data.map(\.score).max() ?? 100
                let stepX = geometry.size.width / CGFloat(max(data.count - 1, 1))
                for (index, point) in data.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geometry.size.height * (1 - point.score / maxValue)
                    index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Theme.ink, lineWidth: 2.5)
        }
    }
}

#Preview {
    StorySummaryView(
        story: Story(
            id: "1", childId: "child1",
            storyTitle: "The Magical Forest Adventure",
            storyContent: "Once upon a time…",
            parentPrompt: "Loves adventures",
            storytellingTone: "calming",
            initialState: "normal",
            startTime: Date(), endTime: Date(),
            duration: 900, sleepOnsetTime: Date(),
            completed: true,
            initialDriftScore: 0, finalDriftScore: 95,
            driftScoreHistory: [0, 15, 25, 40, 55, 68, 78, 85, 92, 95],
            generatedImages: [], modelUsed: nil,
            createdAt: Date(), updatedAt: Date()
        ),
        driftHistory: [0, 15, 25, 40, 55, 68, 78, 85, 92, 95],
        duration: 900,
        onDismiss: {}
    )
}
