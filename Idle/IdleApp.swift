import SwiftUI

@main
struct IdleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthManager()
    @StateObject private var eyeTracking = EyeTrackingManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(eyeTracking)
                .preferredColorScheme(.dark)
        }
    }
}
