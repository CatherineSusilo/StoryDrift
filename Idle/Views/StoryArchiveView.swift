import SwiftUI

struct StoryArchiveView: View {
    @State private var stories: [Story] = []
    @State private var isLoading = true
    @State private var sortBy: SortOption = .date
    @EnvironmentObject var authManager: AuthManager

    let childId: String

    var sortedStories: [Story] {
        switch sortBy {
        case .date:     return stories.sorted { $0.generatedAt > $1.generatedAt }
        case .duration: return stories.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        case .drift:    return stories.sorted { ($0.driftScores.last ?? 0) > ($1.driftScores.last ?? 0) }
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("story archive")
                            .font(Theme.titleFont(size: 28))
                            .foregroundColor(Theme.ink)
                        Text("\(stories.count) stories")
                            .font(Theme.bodyFont(size: 14))
                            .foregroundColor(Theme.inkMuted)
                    }
                    Spacer()
                    Menu {
                        Button(action: { sortBy = .date })     { Label("by date",     systemImage: "calendar") }
                        Button(action: { sortBy = .duration }) { Label("by duration", systemImage: "timer") }
                        Button(action: { sortBy = .drift })    { Label("by drift",    systemImage: "moon.zzz.fill") }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortBy.rawValue.lowercased())
                        }
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.card)
                        .cornerRadius(Theme.radiusSM)
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                if isLoading {
                    Spacer()
                    ProgressView().tint(Theme.ink)
                    Spacer()
                } else if stories.isEmpty {
                    ArchiveEmptyStateView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(sortedStories) { story in
                                StoryArchiveCard(story: story)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task { await loadStories() }
    }

    private func loadStories() async {
        let token = authManager.accessToken ?? UserDefaults.standard.string(forKey: "accessToken")
        do {
            stories = try await APIService.shared.getStories(childId: childId, token: token)
        } catch {
            print("Failed to load stories: \(error)")
        }
        isLoading = false
    }
}

enum SortOption: String {
    case date = "Date"
    case duration = "Duration"
    case drift = "Drift Score"
}

// MARK: - StoryArchiveCard
struct StoryArchiveCard: View {
    let story: Story
    @EnvironmentObject var authManager: AuthManager
    @State private var showingReplay = false
    @State private var showingDetails = false

    private var formattedDate: String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: story.generatedAt)
    }
    private var formattedDuration: String { "\(Int((story.duration ?? 0) / 60)) min" }
    private var finalDrift: Int { Int(story.driftScores.last ?? 0) }

    var body: some View {
        Button(action: { showingReplay = true }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    // Thumbnail
                    StoryThumbnailView(story: story, size: 64)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(story.title)
                            .font(Theme.bodyFont(size: 17))
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.ink)
                            .lineLimit(2)
                        Text(formattedDate)
                            .font(Theme.bodyFont(size: 12))
                            .foregroundColor(Theme.inkMuted)
                    }
                    Spacer()
                    if story.completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.success)
                            .font(.system(size: 22))
                    }
                }

                // Theme chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(story.themes, id: \.self) { theme in
                            Text(theme)
                                .font(Theme.bodyFont(size: 12))
                                .foregroundColor(Theme.ink.opacity(0.75))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.3))
                                .cornerRadius(Theme.radiusSM)
                                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1))
                        }
                    }
                }

                HStack(spacing: 20) {
                    ArchiveStatItem(icon: "timer",         value: formattedDuration)
                    ArchiveStatItem(icon: "book.pages",    value: "\(story.paragraphs.count) parts")
                    ArchiveStatItem(icon: "moon.zzz.fill", value: "\(finalDrift)% drift")
                }
            }
            .padding(16)
            .parchmentCard(cornerRadius: Theme.radiusMD)
        }
        .buttonStyle(ScaleButtonStyle())
        .fullScreenCover(isPresented: $showingReplay) {
            StoryReplayView(story: story)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showingDetails) {
            StoryDetailsView(story: story)
        }
    }
}

struct ArchiveStatItem: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(Theme.inkMuted)
            Text(value).font(Theme.bodyFont(size: 13)).foregroundColor(Theme.ink)
        }
    }
}

struct ArchiveEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 52))
                .foregroundColor(Theme.inkFaint)
            Text("no stories yet")
                .font(Theme.titleFont(size: 24))
                .foregroundColor(Theme.ink)
            Text("start creating magical bedtime stories")
                .font(Theme.bodyFont(size: 15))
                .foregroundColor(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct StoryDetailsView: View {
    let story: Story
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(story.paragraphs.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("part \(i + 1)")
                                    .font(Theme.bodyFont(size: 13))
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.inkMuted)
                                Text(story.paragraphs[i].text)
                                    .font(Theme.bodyFont(size: 16))
                                    .foregroundColor(Theme.ink)
                                    .lineSpacing(4)
                            }
                            .padding(16)
                            .parchmentCard(cornerRadius: Theme.radiusMD)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(story.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done") { dismiss() }
                        .font(Theme.bodyFont(size: 16))
                        .foregroundColor(Theme.ink)
                }
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    StoryArchiveView(childId: "child1")
        .environmentObject(AuthManager())
}
