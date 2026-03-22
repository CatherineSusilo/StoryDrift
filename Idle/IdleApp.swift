import SwiftUI

@main
struct IdleApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var vitalsManager = VitalsManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(vitalsManager)
                .preferredColorScheme(.dark)
        }
    }
}
