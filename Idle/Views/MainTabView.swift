import SwiftUI

struct MainTabView: View {
    @Binding var currentView: AppView
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab = 0
    @State private var children: [ChildProfile] = []
    @State private var selectedChild: ChildProfile?
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            if isLoading {
                LoadingView()
                    .onAppear {
                        Task {
                            await loadChildren()
                        }
                    }
            } else if children.isEmpty {
                // Onboarding for first child
                ChildOnboardingView { child in
                    children.append(child)
                    selectedChild = child
                }
            } else {
                TabView(selection: $selectedTab) {
                    // Dashboard Tab
                    ChildDashboardView(
                        child: .constant(selectedChild ?? children[0]),
                        onStartStory: {
                            currentView = .setup
                        }
                    )
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)
                    
                    // Analytics Tab
                    BehavioralStatsView(child: selectedChild ?? children[0])
                        .tabItem {
                            Label("Analytics", systemImage: "chart.bar.fill")
                        }
                        .tag(1)
                    
                    // Archive Tab
                    StoryArchiveView(childId: selectedChild?.id ?? children[0].id)
                        .tabItem {
                            Label("Stories", systemImage: "book.fill")
                        }
                        .tag(2)
                    
                    // Settings Tab
                    SettingsView(
                        children: $children,
                        selectedChild: $selectedChild
                    )
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
                }
                .accentColor(.purple)
            }
        }
    }
    
    private func loadChildren() async {
        guard let token = authManager.accessToken else {
            isLoading = false
            return
        }
        
        do {
            children = try await APIService.shared.getChildren(token: token)
            if !children.isEmpty {
                selectedChild = children[0]
            }
            isLoading = false
        } catch {
            print("Error loading children: \(error)")
            isLoading = false
        }
    }
}

#Preview {
    MainTabView(currentView: .constant(.dashboard))
        .environmentObject(AuthManager())
        .environmentObject(SmartSpectraManager())
}
