import SwiftUI

struct BehavioralStatsView: View {
    let child: ChildProfile
    var refreshID: UUID = UUID()
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
                        // Prefer dedicated sleep sessions; fall back to story session data
                        let hasSleepData = (sleepStats?.summary.totalSessions ?? 0) > 0
                        if hasSleepData, let sleep = sleepStats {
                            sleepSummaryGrid(
                                sessions:    sleep.summary.totalSessions,
                                avgSleep:    TimeInterval(sleep.summary.avgTimeToSleep),
                                efficiency:  sleep.summary.avgSleepEfficiency,
                                avgDuration: TimeInterval(sleep.summary.avgDuration)
                            )
                        } else if let stats = statistics, stats.summary.totalSessions > 0 {
                            // Fall back: derive sleep summary from story sessions
                            let avgDriftImprovement = stats.summary.avgDriftImprovement ?? 0
                            let efficiency = min(100.0, max(0.0, avgDriftImprovement))
                            sleepSummaryGrid(
                                sessions:    stats.summary.completedSessions,
                                avgSleep:    TimeInterval(stats.summary.avgDuration) * 0.75,
                                efficiency:  efficiency,
                                avgDuration: TimeInterval(stats.summary.avgDuration)
                            )
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
        .onChange(of: refreshID) { Task { await loadStatistics() } }
        .onAppear {
            storyVitalsList = StoryVitalsStore.shared.summaries(for: child.id)
        }
    }

    // MARK: - Insight cards row
    @ViewBuilder
    private func insightCardsRow(stats: ChildStatistics) -> some View {
        // Avg engagement = drift improvement normalized to 0-100%
        // avgDriftImprovement is in drift score points (0-100 scale)
        let driftImprovement = stats.summary.avgDriftImprovement ?? 0
        let avgEngagement = min(100, max(0, Int(driftImprovement)))

        // Favorite themes = top tones from toneDistribution (actual story data)
        let topThemes = topTones(from: stats.toneDistribution)
        let themesText = topThemes.isEmpty ? "none yet" : topThemes.joined(separator: ", ")

        // Learning insight from real stats
        let learningText = buildLearningInsight(stats: stats)

        // Completion rate
        let completionPct = stats.summary.totalSessions > 0
            ? Int((Double(stats.summary.completedSessions) / Double(stats.summary.totalSessions)) * 100)
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
                    value: themesText,
                    valueFont: Theme.titleFont(size: 18)
                )
                InsightCard(
                    icon: "📚",
                    label: "learning insights",
                    value: learningText,
                    valueFont: Theme.bodyFont(size: 15)
                )
                InsightCard(
                    icon: "checkmark.seal.fill",
                    iconColor: Color(red: 0.2, green: 0.65, blue: 0.4),
                    label: "completion rate",
                    value: "\(completionPct)%  (\(stats.summary.completedSessions)/\(stats.summary.totalSessions))",
                    valueFont: Theme.titleFont(size: 22)
                )
            }
            .padding(.vertical, 4)
        }
    }

    /// Returns the top-3 tones sorted by frequency from toneDistribution.
    private func topTones(from distribution: [String: Int]?) -> [String] {
        guard let dist = distribution, !dist.isEmpty else { return [] }
        return dist
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key.capitalized }
    }


    // MARK: - Sleep summary grid
    @ViewBuilder
    private func sleepSummaryGrid(sessions: Int, avgSleep: TimeInterval,
                                   efficiency: Double, avgDuration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("sleep summary")
                .font(Theme.titleFont(size: 22))
                .foregroundColor(Theme.ink)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                MetricCard(title: "sleep sessions",  value: "\(sessions)",             icon: "moon.zzz.fill")
                MetricCard(title: "avg sleep time",  value: formatDuration(avgSleep),   icon: "bed.double.fill")
                MetricCard(title: "efficiency",      value: "\(Int(efficiency))%",     icon: "chart.bar.fill")
                MetricCard(title: "avg duration",    value: formatDuration(avgDuration), icon: "clock.fill")
            }
        }
    }

    // MARK: - Story Vitals Graph Section (SmartSpectra)
    @ViewBuilder
    private var storyVitalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack(alignment: .firstTextBaseline) {
                Text("vitals during storytime")
                    .font(Theme.titleFont(size: 22))
                    .foregroundColor(Theme.ink)
                Spacer()
                // ── Download CSV button ──
                if storyVitalsList.indices.contains(selectedVitalsIndex) {
                    let summary = storyVitalsList[selectedVitalsIndex]
                    ShareLink(
                        item: generateVitalsCSV(summary: summary),
                        preview: SharePreview(
                            "vitals_\(storyTabLabel(summary: summary, index: selectedVitalsIndex)).csv",
                            icon: Image(systemName: "waveform.path.ecg")
                        )
                    ) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 13))
                            Text("Download")
                                .font(Theme.bodyFont(size: 13))
                        }
                        .foregroundColor(Theme.ink)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(Theme.card)
                        .cornerRadius(Theme.radiusSM)
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .stroke(Theme.border, lineWidth: 1.5))
                    }
                }
            }

            // ── Storytime tab picker (date + time) ──
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

    // Date + time label for story tab
    private func storyTabLabel(summary: StoryVitalsSummary, index: Int) -> String {
        guard let snap = summary.snapshots.first else { return "Story \(index + 1)" }
        let f = DateFormatter()
        f.dateFormat = "MMM d  h:mm a"
        return f.string(from: snap.timestamp)
    }

    // Generate CSV string for a single session's vitals
    private func generateVitalsCSV(summary: StoryVitalsSummary) -> String {
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]

        // Filter to rows that have at least one real measurement
        let rows = summary.snapshots.filter { $0.heartRate > 0 || $0.breathingRate > 0 }

        var lines: [String] = []
        lines.append("StoryDrift Vitals Export")
        lines.append("Story ID,\(summary.storyId)")
        lines.append("Child ID,\(summary.childId)")
        if let first = rows.first {
            let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd HH:mm:ss"
            lines.append("Session start,\(d.string(from: first.timestamp))")
        }
        lines.append("")

        // Column headers with units
        lines.append("Timestamp (ISO 8601),Heart Rate (bpm),Breathing Rate (breaths/min)")

        for row in rows {
            let ts = isoFmt.string(from: row.timestamp)
            let hr = row.heartRate > 0 ? String(format: "%.1f", row.heartRate) : ""
            let br = row.breathingRate > 0 ? String(format: "%.1f", row.breathingRate) : ""
            lines.append("\(ts),\(hr),\(br)")
        }

        // Averages row
        let hrVals = rows.map(\.heartRate).filter { $0 > 0 }
        let brVals = rows.map(\.breathingRate).filter { $0 > 0 }
        let avgHR = hrVals.isEmpty ? "" : String(format: "%.1f", hrVals.reduce(0, +) / Double(hrVals.count))
        let avgBR = brVals.isEmpty ? "" : String(format: "%.1f", brVals.reduce(0, +) / Double(brVals.count))
        lines.append("")
        lines.append("Average,,")
        lines.append(",\(avgHR),\(avgBR)")

        return lines.joined(separator: "\n")
    }

    private func buildLearningInsight(stats: ChildStatistics) -> String {
        let avgMin = Int(Double(stats.summary.avgDuration) / 60.0)
        let improvement = stats.summary.avgDriftImprovement ?? 0

        // Best tone from toneDistribution
        let bestTone = stats.toneDistribution?
            .sorted { $0.value > $1.value }
            .first?.key ?? child.preferences?.storytellingTone ?? "calming"

        let effectivenessNote: String
        if improvement >= 50 {
            effectivenessNote = "stories are very effective"
        } else if improvement >= 20 {
            effectivenessNote = "stories help with wind-down"
        } else if stats.summary.completedSessions == 0 {
            effectivenessNote = "complete more stories for insights"
        } else {
            effectivenessNote = "try adjusting story settings"
        }

        if avgMin > 0 {
            return "responds best to \(bestTone) stories, drifts off in ~\(avgMin) min. \(effectivenessNote)."
        } else {
            return "responds best to \(bestTone) stories. \(effectivenessNote)."
        }
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
        guard let token else {
            print("❌ BehavioralStats: No auth token available")
            await MainActor.run { isLoading = false }
            return
        }
        
        print("📊 BehavioralStats: Loading data for child \(child.id)")
        
        do {
            async let statsReq  = APIService.shared.getStatistics(childId: child.id, token: token)
            async let sleepReq  = APIService.shared.getSleepStatistics(childId: child.id, token: token)
            
            let stats = try await statsReq
            let sleep = try await sleepReq
            
            await MainActor.run {
                statistics = stats
                sleepStats = sleep
                isLoading = false
                print("✅ BehavioralStats: Loaded stats (sessions: \(stats.summary.totalSessions)), sleep (sessions: \(sleep.summary.totalSessions))")
            }
        } catch {
            print("❌ BehavioralStats error: \(error)")
            if let apiError = error as? APIError {
                print("   API Error details: \(apiError.localizedDescription)")
            }
            await MainActor.run {
                isLoading = false
            }
        }
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
