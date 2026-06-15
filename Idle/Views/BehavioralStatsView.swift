import SwiftUI

struct BehavioralStatsView: View {
    let child: ChildProfile
    var refreshID: UUID = UUID()
    @EnvironmentObject var authManager: AuthManager
    @State private var statistics: ChildStatistics?
    @State private var sleepStats: SleepStatisticsResponse?
    @State private var isLoading = true

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
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .task { await loadStatistics() }
        .onChange(of: refreshID) { Task { await loadStatistics() } }
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
