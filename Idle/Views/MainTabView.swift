import SwiftUI

struct MainTabView: View {
    @Binding var currentView: AppView
    @Binding var selectedChild: Child?
    @EnvironmentObject var authManager: AuthManager
    @State private var children: [ChildProfile] = []
    @State private var isLoading = true
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            if isLoading {
                LoadingView()
                    .onAppear { Task { await loadChildren() } }
            } else if children.isEmpty {
                ChildOnboardingView { child in
                    children.append(child)
                    selectedChild = child
                }
            } else {
                let child = selectedChild ?? children[0]
                TabView(selection: $selectedTab) {
                    ChildDashboardView(
                        child: .constant(child),
                        onStartStory: {
                            selectedChild = child
                            currentView = .setup
                        }
                    )
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(0)

                    BehavioralStatsView(child: child)
                        .tabItem { Label("Analytics", systemImage: "chart.bar.fill") }
                        .tag(1)

                    StoryArchiveView(childId: child.id)
                        .tabItem { Label("Stories", systemImage: "book.fill") }
                        .tag(2)

                    SettingsView(children: $children, selectedChild: $selectedChild)
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(3)
                }
                .accentColor(.purple)
            }
        }
    }

    private func loadChildren() async {
        guard let token = authManager.accessToken else { isLoading = false; return }
        do {
            children = try await APIService.shared.getChildren(token: token)
            if !children.isEmpty && selectedChild == nil {
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
    MainTabView(currentView: .constant(.dashboard), selectedChild: .constant(nil))
        .environmentObject(AuthManager())
        .environmentObject(VitalsManager())
}
