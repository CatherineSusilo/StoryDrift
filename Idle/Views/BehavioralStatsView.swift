import SwiftUI

struct BehavioralStatsView: View {
    let child: ChildProfile
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
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .task { await loadStatistics() }
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

#Preview {
    BehavioralStatsView(
        child: Child(
            id: "1", userId: "user1", name: "Catherin Jr", age: 5,
            dateOfBirth: nil, avatar: nil,
            createdAt: Date(), updatedAt: Date(),
            preferences: ChildPreferencesModel(
                id: "p1", childId: "1",
                storytellingTone: "calming",
                favoriteThemes: ["mulan", "rainbow", "dragon"],
                defaultInitialState: "normal",
                personality: nil, favoriteMedia: nil, parentGoals: nil
            )
        )
    )
    .environmentObject(AuthManager())
}
