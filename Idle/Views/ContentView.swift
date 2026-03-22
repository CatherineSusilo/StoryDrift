import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var vitalsManager: VitalsManager
    @State private var currentView: AppView = .dashboard
    
    var body: some View {
        ZStack {
            if authManager.isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                MainTabView(currentView: $currentView)
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authManager.isAuthenticated)
    }
}

enum AppView {
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
