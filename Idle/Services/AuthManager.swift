import Foundation
import Combine
import AuthenticationServices

class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var user: User?
    @Published var accessToken: String?
    
    private var authSession: ASWebAuthenticationSession?
    
    // Auth0 configuration
    private let domain = "YOUR_AUTH0_DOMAIN" // TODO: Replace with your Auth0 domain
    private let clientId = "YOUR_AUTH0_CLIENT_ID" // TODO: Replace with your Auth0 client ID
    private let redirectUri = "idle://callback"
    
    override init() {
        super.init()
        checkAuthState()
    }
    
    func login() {
        let authURL = buildAuthURL()
        
        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "idle"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Auth error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            guard let callbackURL = callbackURL,
                  let code = self.extractCode(from: callbackURL) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            self.exchangeCodeForToken(code: code)
        }
        
        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = false
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
        // Check for stored access token
        if let token = UserDefaults.standard.string(forKey: "accessToken") {
            self.accessToken = token
            Task {
                await verifyToken(token)
            }
        } else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
    
    private func verifyToken(_ token: String) async {
        // Verify token with backend
        guard let url = URL(string: "\(APIService.baseURL)/api/auth/verify") else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(APIResponse<User>.self, from: data)
            
            DispatchQueue.main.async {
                if let user = response.data {
                    self.user = user
                    self.isAuthenticated = true
                } else {
                    self.logout()
                }
                self.isLoading = false
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
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid profile email"),
            URLQueryItem(name: "audience", value: "https://\(domain)/api/v2/")
        ]
        
        return components.url!
    }
    
    private func extractCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }
    
    private func exchangeCodeForToken(code: String) {
        guard let url = URL(string: "\(APIService.baseURL)/api/auth/token") else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "code": code,
            "redirect_uri": redirectUri
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Token exchange error: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            do {
                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                
                // Store tokens
                UserDefaults.standard.set(authResponse.token, forKey: "accessToken")
                
                DispatchQueue.main.async {
                    self.accessToken = authResponse.token
                    self.user = authResponse.user
                    self.isAuthenticated = true
                    self.isLoading = false
                }
            } catch {
                print("Token parsing error: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }.resume()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}
