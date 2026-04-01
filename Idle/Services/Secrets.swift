import Foundation

/// Single source of truth for all API keys and config values.
/// Values are read from Info.plist, which is populated at build time from Config.xcconfig.
/// ⚠️  Never hardcode secrets directly in Swift files.
enum Secrets {

    // MARK: - Auth0
    static let auth0Domain: String    = value(for: "AUTH0Domain")
    static let auth0ClientId: String  = value(for: "AUTH0ClientId")
    // auth0Audience is built from auth0Domain in AuthManager — xcconfig can't store URLs with :// safely

    // MARK: - Backend
    // ⚠️  Update this IP to your Mac's current LAN IP each time you switch WiFi.
    // Run `update-ip.sh` from the StoryDrift folder to do it automatically.
    static let apiBaseURL: String = "http://100.70.65.16:3001"

    // MARK: - AI Services
    static let geminiAPIKey: String      = value(for: "GeminiAPIKey")
    static let falAPIKey: String         = value(for: "FalAPIKey")
    static let elevenLabsAPIKey: String  = value(for: "ElevenLabsAPIKey")

    // MARK: - SmartSpectra (Presage)
    /// Get your key from https://physiology.presagetech.com
    /// Returns nil if the key hasn't been set in Config.xcconfig yet.
    static let smartSpectraAPIKey: String? = optionalValue(for: "SmartSpectraAPIKey")

    // MARK: - Private helper
    private static func value(for key: String) -> String {
        guard let val = Bundle.main.infoDictionary?[key] as? String, !val.isEmpty else {
            fatalError("⚠️  Missing key '\(key)' in Info.plist / Config.xcconfig")
        }
        return val
    }

    private static func optionalValue(for key: String) -> String? {
        guard let val = Bundle.main.infoDictionary?[key] as? String,
              !val.isEmpty,
              !val.hasPrefix("YOUR_") else { return nil }
        return val
    }
}
