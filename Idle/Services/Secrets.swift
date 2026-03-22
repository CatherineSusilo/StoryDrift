import Foundation

/// Single source of truth for all API keys and config values.
/// Values are read from Info.plist, which is populated at build time from Config.xcconfig.
/// ⚠️  Never hardcode secrets directly in Swift files.
enum Secrets {

    // MARK: - Auth0
    static let auth0Domain: String   = value(for: "AUTH0Domain")
    static let auth0ClientId: String = value(for: "AUTH0ClientId")

    // MARK: - Backend
    static let apiBaseURL: String    = value(for: "APIBaseURL")

    // MARK: - Private helper
    private static func value(for key: String) -> String {
        guard let val = Bundle.main.infoDictionary?[key] as? String, !val.isEmpty else {
            fatalError("⚠️  Missing key '\(key)' in Info.plist / Config.xcconfig")
        }
        return val
    }
}
