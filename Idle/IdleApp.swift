import SwiftUI

@main
struct IdleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
