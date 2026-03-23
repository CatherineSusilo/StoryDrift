import Foundation
import Combine
import AuthenticationServices

class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var user: User?
    @Published var accessToken: String?
    
    private var authSession: ASWebAuthenticationSession?
    
    // Auth0 configuration — values come from Config.xcconfig (never commit that file)
    private let domain      = Secrets.auth0Domain
    private let clientId    = Secrets.auth0ClientId
    private let redirectUri = "idle://callback"
    // Must exactly match AUTH0_AUDIENCE in the backend's .env
    private let audience    = "https://api.storydrift.app"
    
    override init() {
        super.init()
        checkAuthState()
    }
    
    func login() {
        DispatchQueue.main.async { self.isLoading = true }
        let authURL = buildAuthURL()
        print("🔐 Auth URL: \(authURL.absoluteString)")
        
        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "idle"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }
            
            if let error = error {
                let nsError = error as NSError
                print("❌ Auth error: \(error.localizedDescription)")
                print("❌ Error code: \(nsError.code), domain: \(nsError.domain)")
                // Code 1 = user cancelled, which is fine
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            guard let callbackURL = callbackURL else {
                print("❌ No callback URL received")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            print("✅ Callback URL: \(callbackURL.absoluteString)")
            
            // Check for Auth0 error in callback
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            if let authError = components?.queryItems?.first(where: { $0.name == "error" })?.value,
               let desc = components?.queryItems?.first(where: { $0.name == "error_description" })?.value {
                print("❌ Auth0 error: \(authError) — \(desc)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            guard let code = self.extractCode(from: callbackURL) else {
                print("❌ No code in callback URL")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            print("✅ Got auth code, exchanging for token...")
            self.exchangeCodeForToken(code: code)
        }
        
        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = true
        authSession?.start()
    }
    
    func logout() {
        // Clear stored tokens
        UserDefaults.standard.removeObject(forKey: "accessToken")
        UserDefaults.standard.removeObject(forKey: "refreshToken")
        
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.user = nil
            self.accessToken = nil
        }
    }
    
    private func checkAuthState() {
        if let token = UserDefaults.standard.string(forKey: "accessToken") {
            self.accessToken = token
            DispatchQueue.main.async { self.isLoading = true }
            Task {
                await verifyToken(token)
            }
        }
        // no stored token — stay on login screen, isLoading stays false
    }
    
    private func verifyToken(_ token: String) async {
        // Verify by calling Auth0's /userinfo — if the token is valid we get user info back
        guard let url = URL(string: "https://\(domain)/userinfo") else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 200,
               let userInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = userInfo["email"] as? String {
                // Token still valid — re-fetch profile from backend
                self.fetchOrCreateProfile(accessToken: token)
            } else {
                print("⚠️ Stored token invalid, logging out")
                DispatchQueue.main.async {
                    self.logout()
                    self.isLoading = false
                }
            }
        } catch {
            print("Token verification error: \(error)")
            DispatchQueue.main.async {
                self.logout()
                self.isLoading = false
            }
        }
    }
    
    private func buildAuthURL() -> URL {
        var valueAllowed = CharacterSet.urlQueryAllowed
        valueAllowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")

        func encode(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? s
        }

        let parts = [
            "client_id=\(encode(clientId))",
            "redirect_uri=\(encode(redirectUri))",
            "response_type=code",
            "scope=\(encode("openid profile email offline_access"))",
            "audience=\(encode(audience))"
        ]

        let urlString = "https://\(domain)/authorize?\(parts.joined(separator: "&"))"
        print("🔐 Full auth URL: \(urlString)")
        return URL(string: urlString)!
    }
    
    private func extractCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }
    
    private func exchangeCodeForToken(code: String) {
        guard let url = URL(string: "https://\(domain)/oauth/token") else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectUri
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Token exchange error: \(error)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            guard let accessToken = json["access_token"] as? String else {
                let raw = String(data: data, encoding: .utf8) ?? "nil"
                print("❌ Token exchange failed: \(raw)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            // Decode user info from id_token (JWT) — avoids calling /userinfo
            // which rejects custom-audience access tokens
            let idToken = json["id_token"] as? String
            let userInfo = idToken.flatMap { Self.decodeJWTPayload($0) } ?? [:]

            let email   = userInfo["email"] as? String ?? ""
            let name    = userInfo["name"] as? String
            let picture = userInfo["picture"] as? String

            print("✅ Got access token for \(email), syncing profile with backend...")
            UserDefaults.standard.set(accessToken, forKey: "accessToken")
            self.syncProfile(accessToken: accessToken, email: email, name: name, picture: picture)
        }.resume()
    }

    /// Decode the payload of a JWT without verifying the signature (verification is done server-side)
    private static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to multiple of 4
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func syncProfile(accessToken: String, email: String, name: String?, picture: String?) {
        guard let profileURL = URL(string: "\(APIService.baseURL)/api/auth/profile") else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }

        var req = URLRequest(url: profileURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["email": email]
        if let name = name { body["name"] = name }
        if let picture = picture { body["picture"] = picture }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Profile sync error: \(error)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            do {
                let user = try JSONDecoder().decode(User.self, from: data)
                DispatchQueue.main.async {
                    self.accessToken = accessToken
                    self.user = user
                    self.isAuthenticated = true
                    self.isLoading = false
                    print("✅ Logged in as \(user.email)")
                }
            } catch {
                let raw = String(data: data, encoding: .utf8) ?? "nil"
                print("❌ Profile parse error: \(error)\nRaw: \(raw)")
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }

    private func fetchOrCreateProfile(accessToken: String) {
        // Called when verifying a stored token — we don't have the id_token anymore,
        // so just call the backend profile endpoint directly (it will find the existing user)
        guard let profileURL = URL(string: "\(APIService.baseURL)/api/auth/profile") else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }

        // We need email for the backend — decode from stored access token if possible,
        // otherwise use empty string (backend finds user by auth0Id from token sub claim)
        var req = URLRequest(url: profileURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": ""])

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }

            guard let data = data else {
                DispatchQueue.main.async { self.logout(); self.isLoading = false }
                return
            }

            do {
                let user = try JSONDecoder().decode(User.self, from: data)
                DispatchQueue.main.async {
                    self.user = user
                    self.isAuthenticated = true
                    self.isLoading = false
                }
            } catch {
                print("⚠️ Stored token invalid: \(error)")
                DispatchQueue.main.async { self.logout(); self.isLoading = false }
            }
        }.resume()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Must return the app's actual connected window — ASPresentationAnchor() alone
        // gives an unconnected window which causes the session to be cancelled immediately.
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}
