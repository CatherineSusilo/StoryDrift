import SwiftUI
import SmartSpectraSwiftSDK

@main
struct IdleApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var spectraManager = SmartSpectraManager()
    
    init() {
        // Initialize SmartSpectra SDK
        SmartSpectraSwiftSDK.shared.setApiKey("BGvdA0lLfe70oLSvugIs31tIzrGU6KqI8Q5wG5lj")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(spectraManager)
                .preferredColorScheme(.dark)
        }
    }
}
