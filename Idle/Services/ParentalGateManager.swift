import Foundation
import Combine
import CommonCrypto

/// Manages parent/child mode and the 6-digit parental passcode.
/// @MainActor ensures all @Published mutations happen on the main thread.
@MainActor
final class ParentalGateManager: ObservableObject {

    static let shared = ParentalGateManager()

    // MARK: - Published state
    @Published private(set) var isParentMode: Bool = false
    @Published private(set) var hasPasscode: Bool = true

    // MARK: - Keys
    private let kPasscodeHash = "parentalGate.passcodeHash"
    private let kIsParentMode = "parentalGate.isParentMode"

    // MARK: - Init
    init() {
        // If no passcode has ever been set, seed the default "000000"
        if UserDefaults.standard.string(forKey: kPasscodeHash) == nil {
            UserDefaults.standard.set(sha256("000000"), forKey: kPasscodeHash)
        }
        isParentMode = UserDefaults.standard.bool(forKey: kIsParentMode)
    }

    // MARK: - Public API

    /// Save a new passcode locally and sync to backend.
    func setPasscode(_ pin: String, token: String? = nil) {
        UserDefaults.standard.set(sha256(pin), forKey: kPasscodeHash)
        hasPasscode = true
        enterParentMode()
        if let token { Task { await syncPasscodeToBackend(pin: pin, token: token) } }
    }

    /// Verify locally first (instant), then confirm against backend if online.
    func verify(_ pin: String) -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: kPasscodeHash) else { return false }
        return sha256(pin) == stored
    }

    /// Verify against backend; falls back to local if offline.
    func verifyWithBackend(pin: String, token: String) async -> Bool {
        guard let url = URL(string: "\(APIService.baseURL)/api/auth/passcode/verify") else { return verify(pin) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["passcode": pin])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let valid = json["valid"] as? Bool else { return verify(pin) }
        if valid {
            UserDefaults.standard.set(sha256(pin), forKey: kPasscodeHash)
            hasPasscode = true
        }
        return valid
    }

    /// Pull passcode existence from backend; seeds default if missing.
    func syncFromBackend(token: String) async {
        guard let url = URL(string: "\(APIService.baseURL)/api/auth/passcode/exists") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exists = json["exists"] as? Bool else { return }
        if !exists {
            Task { await syncPasscodeToBackend(pin: "000000", token: token) }
        }
    }

    func enterParentMode() {
        isParentMode = true
        UserDefaults.standard.set(true, forKey: kIsParentMode)
    }

    func enterChildMode() {
        isParentMode = false
        UserDefaults.standard.set(false, forKey: kIsParentMode)
    }

    func resetPasscode(newPin: String, token: String? = nil) {
        setPasscode(newPin, token: token)
    }

    func syncPasscodeToBackendPublic(pin: String, token: String) async {
        await syncPasscodeToBackend(pin: pin, token: token)
    }

    // MARK: - Private

    private func syncPasscodeToBackend(pin: String, token: String) async {
        guard let url = URL(string: "\(APIService.baseURL)/api/auth/passcode/set") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["passcode": pin])
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse {
            print("[ParentalGate] Synced to backend: \(http.statusCode)")
        }
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
