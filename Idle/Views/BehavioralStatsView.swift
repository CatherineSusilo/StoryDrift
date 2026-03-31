import SwiftUI

struct BehavioralStatsView: View {
    let child: ChildProfile
    @EnvironmentObject var authManager: AuthManager
    @State private var statistics: ChildStatistics?
    @State private var sleepStats: SleepStatisticsResponse?
    @State private var isLoading = true
    // SmartSpectra vitals per story (read from local store)
    @State private var storyVitalsList: [StoryVitalsSummary] = []
    @State private var selectedVitalsIndex: Int = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Header ──
                    Text("behavioral insights")
                        .font(Theme.titleFont(size: 32))
                        .foregroundColor(Theme.ink)
                        .padding(.top, 20)

                    // ── Child name chip ──
                    Text(child.name)
                        .font(Theme.bodyFont(size: 17))
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.ink)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Theme.card)
                        .cornerRadius(Theme.radiusSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .stroke(Theme.borderActive, lineWidth: 2)
                        )

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView().tint(Theme.ink)
                            Spacer()
                        }
                        .padding(40)
                    } else {
                        // ── Story stats grid ──
                        if let stats = statistics {
                            insightCardsRow(stats: stats)
                        }

                        // ── Sleep stats ──
                        if let sleep = sleepStats {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("sleep summary")
                                    .font(Theme.titleFont(size: 22))
                                    .foregroundColor(Theme.ink)

                                LazyVGrid(
                                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                    spacing: 12
                                ) {
                                    MetricCard(title: "sleep sessions",  value: "\(sleep.summary.totalSessions)",           icon: "moon.zzz.fill")
                                    MetricCard(title: "avg sleep time",  value: formatDuration(TimeInterval(sleep.summary.avgTimeToSleep)), icon: "bed.double.fill")
                                    MetricCard(title: "efficiency",      value: "\(Int(sleep.summary.avgSleepEfficiency))%", icon: "chart.bar.fill")
                                    MetricCard(title: "avg duration",    value: formatDuration(TimeInterval(sleep.summary.avgDuration)),    icon: "clock.fill")
                                }
                            }
                        }

                        if statistics == nil && sleepStats == nil {
                            parchmentEmptyState
                        }

                        // ── Story Vitals (SmartSpectra) ──
                        if !storyVitalsList.isEmpty {
                            storyVitalsSection
                        }
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .task { await loadStatistics() }
        .onAppear {
            storyVitalsList = StoryVitalsStore.shared.summaries(for: child.id)
        }
    }

    // MARK: - Insight cards row (matches the 4-card row in the screenshot)
    @ViewBuilder
    private func insightCardsRow(stats: ChildStatistics) -> some View {
        // Build the four insight card data points
        let themes = (child.preferences?.favoriteThemes ?? []).prefix(3).joined(separator: ", ")
        let learningText = buildLearningInsight(stats: stats)
        let avgEngagement = stats.summary.completedSessions > 0
            ? Int((Double(stats.summary.completedSessions) / Double(max(stats.summary.totalSessions, 1))) * 100)
            : 0

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                InsightCard(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: Theme.ink.opacity(0.75),
                    label: "avg engagement",
                    value: "\(avgEngagement)%",
                    valueFont: Theme.titleFont(size: 30)
                )
                InsightCard(
                    icon: "face.smiling",
                    iconColor: Color(red: 0.9, green: 0.45, blue: 0.45),
                    label: "favorite themes",
                    value: themes.isEmpty ? "none yet" : themes,
                    valueFont: Theme.titleFont(size: 20)
                )
                InsightCard(
                    icon: "📚",
                    label: "learning insights",
                    value: learningText,
                    valueFont: Theme.bodyFont(size: 15)
                )
                InsightCard(
                    icon: "⭐",
                    label: "favorite characters",
                    value: "coming soon",
                    valueFont: Theme.titleFont(size: 20)
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Story Vitals Graph Section (SmartSpectra)
    @ViewBuilder
    private var storyVitalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("vitals during storytime")
                .font(Theme.titleFont(size: 22))
                .foregroundColor(Theme.ink)

            // ── Storytime tab picker ──
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(storyVitalsList.indices, id: \.self) { i in
                        let summary = storyVitalsList[i]
                        let label = storyTabLabel(summary: summary, index: i)
                        Button(action: { selectedVitalsIndex = i }) {
                            Text(label)
                                .font(Theme.bodyFont(size: 13))
                                .foregroundColor(selectedVitalsIndex == i ? Theme.card : Theme.inkMuted)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 14)
                                .background(
                                    Capsule()
                                        .fill(selectedVitalsIndex == i ? Theme.ink : Theme.card)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // ── Graphs for selected session ──
            if storyVitalsList.indices.contains(selectedVitalsIndex) {
                let summary = storyVitalsList[selectedVitalsIndex]

                VStack(spacing: 16) {
                    VitalsLineGraph(
                        snapshots: summary.snapshots,
                        metric: .heartRate,
                        color: Color(red: 0.75, green: 0.18, blue: 0.18)
                    )
                    VitalsLineGraph(
                        snapshots: summary.snapshots,
                        metric: .breathingRate,
                        color: Color(red: 0.15, green: 0.50, blue: 0.65)
                    )
                }
            }
        }
    }

    private func storyTabLabel(summary: StoryVitalsSummary, index: Int) -> String {
        guard let snap = summary.snapshots.first else { return "Story \(index + 1)" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: snap.timestamp)
    }

    private func buildLearningInsight(stats: ChildStatistics) -> String {
        let tone = child.preferences?.storytellingTone ?? "calming"
        let avgMin = Int(Double(stats.summary.avgDuration) / 60.0)
        return "responds best to \(tone) storytelling, usually drifts off in ~\(avgMin) min"
    }

    // MARK: - Empty state
    private var parchmentEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar")
                .font(.system(size: 44))
                .foregroundColor(Theme.inkFaint)
            Text("no statistics available yet")
                .font(Theme.bodyFont(size: 17))
                .foregroundColor(Theme.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(44)
    }

    // MARK: - Data loading
    private func loadStatistics() async {
        let token = authManager.accessToken ?? UserDefaults.standard.string(forKey: "accessToken")
        guard let token else { isLoading = false; return }
        async let storyTask: ChildStatistics? = try? APIService.shared.getStatistics(childId: child.id, token: token)
        async let sleepTask: SleepStatisticsResponse? = try? APIService.shared.getSleepStatistics(childId: child.id, token: token)
        statistics = await storyTask
        sleepStats = await sleepTask
        isLoading = false
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        "\(Int(seconds / 60))m"
    }
}

// MARK: - InsightCard (the large horizontal-scroll cards shown in the screenshot)
struct InsightCard: View {
    var icon: String          // SF Symbol name OR single emoji
    var iconColor: Color = Theme.ink
    let label: String
    let value: String
    var valueFont: Font = Theme.bodyFont(size: 18)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon — either SF Symbol or emoji
            if icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 28))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
            }

            Text(label)
                .font(Theme.bodyFont(size: 14))
                .foregroundColor(Theme.inkMuted)

            Text(value)
                .font(valueFont)
                .foregroundColor(Theme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 200, alignment: .leading)
        .parchmentCard(cornerRadius: Theme.radiusMD)
    }
}

// MARK: - MetricCard (used in sleep stats grid)
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(Theme.inkMuted)

            Text(value)
                .font(Theme.titleFont(size: 26))
                .foregroundColor(Theme.ink)

            Text(title)
                .font(Theme.bodyFont(size: 13))
                .foregroundColor(Theme.inkMuted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .parchmentCard(cornerRadius: Theme.radiusMD)
    }
}

// MARK: - VitalsLineGraph
/// Draws a line graph for heart rate or breathing rate over a story session.
struct VitalsLineGraph: View {

    enum Metric { case heartRate, breathingRate }

    let snapshots: [StoryVitalsSnapshot]
    let metric: Metric
    let color: Color

    private var values: [Double] {
        snapshots.map { metric == .heartRate ? $0.heartRate : $0.breathingRate }
    }
    private var title: String  { metric == .heartRate ? "Heart Rate" : "Breathing Rate" }
    private var unit: String   { metric == .heartRate ? "bpm"        : "br/min" }
    private var icon: String   { metric == .heartRate ? "heart.fill" : "wind" }

    private var nonZero: [Double] { values.filter { $0 > 0 } }
    private var minVal: Double  { (nonZero.min() ?? 0) * 0.92 }
    private var maxVal: Double  { (nonZero.max() ?? 1) * 1.08 }
    private var avgVal: Double  {
        nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header row
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(Theme.titleFont(size: 17))
                    .foregroundColor(Theme.ink)
                Spacer()
                if avgVal > 0 {
                    Text("avg \(Int(avgVal.rounded())) \(unit)")
                        .font(Theme.bodyFont(size: 13))
                        .foregroundColor(Theme.inkMuted)
                }
            }

            if nonZero.isEmpty {
                // No data state
                HStack {
                    Spacer()
                    Text("no data recorded")
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(Theme.inkFaint)
                    Spacer()
                }
                .frame(height: 120)
            } else {
                // Y-axis labels + canvas
                HStack(alignment: .top, spacing: 6) {
                    // Y labels
                    VStack(alignment: .trailing) {
                        Text("\(Int(maxVal.rounded()))")
                            .font(Theme.bodyFont(size: 10))
                            .foregroundColor(Theme.inkFaint)
                        Spacer()
                        Text("\(Int(minVal.rounded()))")
                            .font(Theme.bodyFont(size: 10))
                            .foregroundColor(Theme.inkFaint)
                    }
                    .frame(width: 28, height: 120)

                    // Line graph canvas
                    Canvas { ctx, size in
                        guard values.count > 1 else { return }

                        let range = maxVal - minVal
                        guard range > 0 else { return }

                        // Draw gridlines
                        for fraction in [0.25, 0.5, 0.75] {
                            let y = size.height * (1 - fraction)
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            ctx.stroke(path, with: .color(Theme.ink.opacity(0.08)), lineWidth: 1)
                        }

                        // Build line path (skip zero values — bridge over gaps)
                        var linePath = Path()
                        var started = false
                        let step = size.width / CGFloat(values.count - 1)

                        for (i, v) in values.enumerated() {
                            guard v > 0 else { started = false; continue }
                            let x = CGFloat(i) * step
                            let y = size.height * CGFloat(1 - (v - minVal) / range)
                            let pt = CGPoint(x: x, y: y)
                            if !started { linePath.move(to: pt); started = true }
                            else { linePath.addLine(to: pt) }
                        }
                        ctx.stroke(linePath, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // Fill area under line
                        var fillPath = linePath
                        // Close fill down to baseline
                        let enumerated = Array(values.enumerated())
                        if let last = enumerated.last(where: { $0.element > 0 }) {
                            let x = CGFloat(last.offset) * step
                            fillPath.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        if let first = enumerated.first(where: { $0.element > 0 }) {
                            let x = CGFloat(first.offset) * step
                            fillPath.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        fillPath.closeSubpath()
                        ctx.fill(fillPath, with: .color(color.opacity(0.12)))

                        // Dots on data points
                        for (i, v) in values.enumerated() where v > 0 {
                            let x = CGFloat(i) * step
                            let y = size.height * CGFloat(1 - (v - minVal) / range)
                            let rect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                            ctx.fill(Path(ellipseIn: rect), with: .color(color))
                        }
                    }
                    .frame(height: 120)
                    .background(Theme.card.opacity(0.3))
                    .cornerRadius(6)
                }

                // X-axis time labels
                HStack {
                    if let first = snapshots.first(where: { metric == .heartRate ? $0.heartRate > 0 : $0.breathingRate > 0 }) {
                        Text(timeLabel(first.timestamp))
                            .font(Theme.bodyFont(size: 10))
                            .foregroundColor(Theme.inkFaint)
                    }
                    Spacer()
                    if let last = snapshots.last(where: { metric == .heartRate ? $0.heartRate > 0 : $0.breathingRate > 0 }) {
                        Text(timeLabel(last.timestamp))
                            .font(Theme.bodyFont(size: 10))
                            .foregroundColor(Theme.inkFaint)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(16)
        .parchmentCard(cornerRadius: Theme.radiusMD)
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

#Preview {
    BehavioralStatsView(
        child: Child(
            id: "1", userId: "user1", name: "Catherin Jr", age: 5,
            dateOfBirth: nil, avatar: nil,
            createdAt: Date(), updatedAt: Date(),
            preferences: ChildPreferencesModel(
                storytellingTone: "calming",
                favoriteThemes: ["mulan", "rainbow", "dragon"],
                defaultInitialState: "normal",
                personality: nil, favoriteMedia: nil, parentGoals: nil
            )
        )
    )
    .environmentObject(AuthManager())
}
