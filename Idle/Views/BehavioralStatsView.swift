import SwiftUI

struct BehavioralStatsView: View {
    let child: ChildProfile
    @State private var statistics: ChildStatistics?
    @State private var sleepStats: SleepStatisticsResponse?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                Text("Analytics")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)

                if isLoading {
                    ProgressView().tint(.white).padding(40)
                } else {
                    // Story stats
                    if let stats = statistics {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            MetricCard(title: "Total Stories",
                                       value: "\(stats.summary.totalSessions)",
                                       icon: "book.fill", color: .purple)
                            MetricCard(title: "Completed",
                                       value: "\(stats.summary.completedSessions)",
                                       icon: "checkmark.circle.fill", color: .green)
                            MetricCard(title: "Avg Duration",
                                       value: formatDuration(TimeInterval(stats.summary.avgDuration)),
                                       icon: "timer.fill", color: .orange)
                            if let improvement = stats.summary.avgDriftImprovement {
                                MetricCard(title: "Drift Improve",
                                           value: String(format: "%.1f", improvement),
                                           icon: "arrow.down.heart.fill", color: .blue)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Sleep stats
                    if let sleep = sleepStats {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sleep Summary")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                MetricCard(title: "Sleep Sessions",
                                           value: "\(sleep.summary.totalSessions)",
                                           icon: "moon.zzz.fill", color: .indigo)
                                MetricCard(title: "Avg Sleep Time",
                                           value: formatDuration(TimeInterval(sleep.summary.avgTimeToSleep)),
                                           icon: "bed.double.fill", color: .cyan)
                                MetricCard(title: "Efficiency",
                                           value: "\(Int(sleep.summary.avgSleepEfficiency))%",
                                           icon: "chart.bar.fill", color: .mint)
                                MetricCard(title: "Avg Duration",
                                           value: formatDuration(TimeInterval(sleep.summary.avgDuration)),
                                           icon: "clock.fill", color: .teal)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
                        .padding(.horizontal)
                    }

                    if statistics == nil && sleepStats == nil {
                        EmptyStateView(icon: "chart.bar", message: "No statistics available yet.")
                            .padding(40)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.15, green: 0.05, blue: 0.25)
                ]),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .task { await loadStatistics() }
    }

    private func loadStatistics() async {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            isLoading = false; return
        }
        async let storyTask: ChildStatistics? = try? APIService.shared.getStatistics(childId: child.id, token: token)
        async let sleepTask: SleepStatisticsResponse? = try? APIService.shared.getSleepStatistics(childId: child.id, token: token)
        statistics = await storyTask
        sleepStats = await sleepTask
        isLoading = false
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes)m"
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}

#Preview {
    BehavioralStatsView(
        child: Child(
            id: "1", userId: "user1", name: "Emma", age: 5,
            dateOfBirth: nil, avatar: nil,
            createdAt: Date(), updatedAt: Date(), preferences: nil
        )
    )
}
