import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var vitalsManager: VitalsManager

    @State private var currentView: AppView = .dashboard
    @State private var storyConfig: StoryConfig?
    @State private var activeStory: Story?
    @State private var driftHistory: [Double] = []
    @State private var storyDuration: TimeInterval = 0
    @State private var selectedChild: Child?
    @State private var dashboardRefreshID: UUID = UUID()

    var body: some View {
        ZStack {
            if authManager.isLoading {
                LoadingView()

            } else if authManager.isAuthenticated {
                switch currentView {
                case .dashboard, .onboarding, .roadmap:
                    MainTabView(
                        currentView: $currentView,
                        selectedChild: $selectedChild,
                        dashboardRefreshID: dashboardRefreshID
                    )

                case .setup:
                    if let child = selectedChild {
                        StorySetupView(
                            child: .constant(child),
                            onStartStory: { config in
                                storyConfig = config
                                currentView = .story
                                Task { await generateStory(config: config) }
                            },
                            onBack: { currentView = .dashboard }
                        )
                        .transition(.move(edge: .trailing))
                    } else {
                        // No child selected — go back
                        Color.clear.onAppear { currentView = .dashboard }
                    }

                case .story:
                    if let story = activeStory {
                        StoryPlaybackView(
                            story: story,
                            onComplete: { history, duration in
                                driftHistory = history
                                storyDuration = duration
                                currentView = .summary
                                // Persist completion to backend
                                Task { await saveCompletion(story: story, history: history, duration: duration) }
                            }
                        )
                        .transition(.opacity)
                    } else {
                        // Still generating — show loading
                        LoadingView()
                    }

                case .summary:
                    if let story = activeStory {
                        StorySummaryView(
                            story: story,
                            driftHistory: driftHistory,
                            duration: storyDuration,
                            onDismiss: {
                                activeStory = nil
                                driftHistory = []
                                storyDuration = 0
                                dashboardRefreshID = UUID()   // trigger dashboard reload
                                currentView = .dashboard
                            }
                        )
                        .transition(.move(edge: .bottom))
                    } else {
                        Color.clear.onAppear { currentView = .dashboard }
                    }
                }

            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authManager.isAuthenticated)
        .animation(.easeInOut, value: currentView)
    }

    private func generateStory(config: StoryConfig) async {
        guard let token = authManager.accessToken else { return }
        do {
            let story = try await APIService.shared.generateStory(config: config, token: token)
            await MainActor.run { activeStory = story }
        } catch {
            print("❌ Story generation failed: \(error)")
            await MainActor.run { currentView = .dashboard }
        }
    }

    private func saveCompletion(story: Story, history: [Double], duration: TimeInterval) async {
        guard let token = authManager.accessToken else { return }
        let finalScore = Int(history.last ?? 0)
        let historyInts = history.map { Int($0) }
        do {
            try await APIService.shared.updateStory(
                storyId: story.id,
                completed: true,
                duration: Int(duration),
                finalDriftScore: finalScore,
                driftScoreHistory: historyInts,
                token: token
            )
            print("✅ Story \(story.id) saved as completed (drift: \(finalScore)%)")
        } catch {
            print("⚠️ Could not save story completion: \(error)")
        }
    }
}

enum AppView: Equatable {
    case dashboard
    case onboarding
    case roadmap
    case setup
    case story
    case summary
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(VitalsManager())
}
