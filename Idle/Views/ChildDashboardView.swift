import SwiftUI

struct ChildDashboardView: View {
    @Binding var child: ChildProfile
    var refreshID: UUID = UUID()
    @EnvironmentObject var vitalsManager: VitalsManager
    @EnvironmentObject var authManager: AuthManager
    @State private var recentStories: [Story] = []
    @State private var statistics: ChildStatistics?
    let onStartStory: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Greeting header ──
                    VStack(alignment: .leading, spacing: 4) {
                        Text("good evening,")
                            .font(Theme.bodyFont(size: 18))
                            .foregroundColor(Theme.inkMuted)
                        Text(child.name)
                            .font(Theme.titleFont(size: 38))
                            .foregroundColor(Theme.ink)
                    }
                    .padding(.top, 24)

                    // ── Start Story CTA ──
                    Button(action: onStartStory) {
                        HStack(spacing: 12) {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 22))
                            Text("start bedtime story")
                                .font(Theme.bodyFont(size: 20))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .foregroundColor(Theme.card)
                        .background(Theme.ink)
                        .cornerRadius(Theme.radiusMD)
                        .shadow(color: Theme.ink.opacity(0.25), radius: 6, x: 0, y: 3)
                    }

                    // ── Quick stats ──
                    if let stats = statistics {
                        QuickStatsCard(stats: stats)
                    }

                    // ── Recent Stories ──
                    VStack(alignment: .leading, spacing: 14) {
                        Text("recent stories")
                            .font(Theme.titleFont(size: 22))
                            .foregroundColor(Theme.ink)

                        if recentStories.isEmpty {
                            EmptyStateView(
                                icon: "book",
                                message: "no stories yet.\nstart your first bedtime adventure!"
                            )
                        } else {
                            ForEach(recentStories.prefix(3)) { story in
                                StoryCardView(story: story)
                            }
                        }
                    }

                    // ── Drift meter preview ──
                    if vitalsManager.isMonitoring {
                        DriftMeterPreview()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .task { await loadDashboardData() }
        .onChange(of: refreshID) { Task { await loadDashboardData() } }
    }

    private func loadDashboardData() async {
        let token = authManager.accessToken ?? UserDefaults.standard.string(forKey: "accessToken")
        guard let token else {
            print("❌ Dashboard: No auth token available")
            return
        }
        
        print("📊 Dashboard: Loading data for child \(child.id)")
        
        do {
            async let storiesTask = APIService.shared.getStories(childId: child.id, token: token)
            async let statsTask   = APIService.shared.getStatistics(childId: child.id, token: token)
            
            let stories = try await storiesTask
            let stats = try await statsTask
            
            await MainActor.run {
                recentStories = stories.filter { $0.storytellingTone != "educational" }
                statistics = stats
                print("✅ Dashboard: Loaded \(stories.count) stories, stats: \(stats.summary.totalSessions) sessions")
            }
        } catch {
            print("❌ Dashboard error: \(error)")
            if let apiError = error as? APIError {
                print("   API Error details: \(apiError.localizedDescription)")
            }
        }
    }
}

// MARK: - QuickStatsCard
struct QuickStatsCard: View {
    let stats: ChildStatistics

    var body: some View {
        HStack(spacing: 0) {
            StatItem(value: "\(stats.summary.totalSessions)",
                     label: "stories",       icon: "book.fill")
            divider
            StatItem(value: formatDuration(TimeInterval(stats.summary.avgDuration)),
                     label: "avg sleep",     icon: "moon.zzz.fill")
            divider
            StatItem(value: "\(stats.summary.completedSessions)/\(stats.summary.totalSessions)",
                     label: "completed",     icon: "checkmark.circle.fill")
        }
        .parchmentCard(cornerRadius: Theme.radiusMD)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1.5)
            .padding(.vertical, 12)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        "\(Int(seconds / 60))m"
    }
}

// MARK: - StatItem
struct StatItem: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Theme.inkMuted)
            Text(value)
                .font(Theme.titleFont(size: 22))
                .foregroundColor(Theme.ink)
            Text(label)
                .font(Theme.bodyFont(size: 12))
                .foregroundColor(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - StoryCardView
struct StoryCardView: View {
    let story: Story

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            StoryThumbnailView(story: story, size: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(story.title)
                    .font(Theme.bodyFont(size: 17))
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.ink)
                    .lineLimit(2)

                Text(story.themes.joined(separator: ", "))
                    .font(Theme.bodyFont(size: 13))
                    .foregroundColor(Theme.inkMuted)

                Text(formatDate(story.startTime))
                    .font(Theme.bodyFont(size: 12))
                    .foregroundColor(Theme.inkFaint)
            }

            Spacer()

            if story.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.success)
                    .font(.system(size: 20))
            }
        }
        .padding(14)
        .parchmentCard(cornerRadius: Theme.radiusMD)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - DriftMeterPreview
struct DriftMeterPreview: View {
    @EnvironmentObject var vitalsManager: VitalsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("drift score")
                    .font(Theme.bodyFont(size: 17))
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.ink)
                Spacer()
                Text("\(vitalsManager.getDriftPercentage())%")
                    .font(Theme.titleFont(size: 28))
                    .foregroundColor(Theme.ink)
            }
            ProgressView(value: (vitalsManager.driftScore.isFinite ? min(max(vitalsManager.driftScore, 0), 100) : 0) / 100)
                .tint(Theme.ink)
                .scaleEffect(y: 1.6)
                .padding(.vertical, 4)
            Text(vitalsManager.getDriftStatus())
                .font(Theme.bodyFont(size: 13))
                .foregroundColor(Theme.inkMuted)
        }
        .padding(16)
        .parchmentCard(cornerRadius: Theme.radiusMD)
    }
}

// MARK: - EmptyStateView
struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(Theme.inkFaint)
            Text(message)
                .font(Theme.bodyFont(size: 16))
                .foregroundColor(Theme.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

#Preview {
    ChildDashboardView(
        child: .constant(Child(
            id: "1", userId: "user1", name: "Catherin Jr", age: 5,
            dateOfBirth: nil, avatar: nil,
            createdAt: Date(), updatedAt: Date(), preferences: nil
        )),
        onStartStory: {}
    )
    .environmentObject(VitalsManager())
    .environmentObject(AuthManager())
}

// MARK: - StoryThumbnailView
// Shows the first image of a story. If generatedImages is empty but imageJobId exists,
// fetches the first available image from the background job endpoint.
struct StoryThumbnailView: View {
    let story: Story
    let size: CGFloat

    @State private var resolvedUrl: URL? = nil
    @State private var hasFetched = false

    private var directUrl: URL? {
        guard let first = story.images.first(where: { !$0.isEmpty }),
              let url = URL(string: first) else { return nil }
        return url
    }

    var body: some View {
        Group {
            if let url = resolvedUrl ?? directUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        .clipped()
        .task { await fetchIfNeeded() }
    }

    private var placeholderView: some View {
        ZStack {
            Theme.accent.opacity(0.3)
            Image(systemName: "book.fill")
                .foregroundColor(Theme.inkMuted)
                .font(.system(size: size * 0.35))
        }
    }

    private func fetchIfNeeded() async {
        guard directUrl == nil, !hasFetched,
              let jobId = story.imageJobId, !jobId.isEmpty else { return }
        hasFetched = true
        let token = UserDefaults.standard.string(forKey: "accessToken") ?? ""
        guard !token.isEmpty,
              let url = URL(string: "\(APIService.baseURL)/api/generate/story-images/\(jobId)") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [String],
              let first = images.first(where: { !$0.isEmpty }),
              let parsed = URL(string: first) else { return }
        await MainActor.run { resolvedUrl = parsed }
    }
}
