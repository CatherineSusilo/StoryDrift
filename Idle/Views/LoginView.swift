import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Logo & title ──
                VStack(spacing: 12) {
                    Image("StoryDriftLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)

                    Text("StoryDrift")
                        .font(Theme.bodyFont(size: 24))
                        .foregroundColor(Theme.inkMuted)
                        .italic()
                    
                    Text("dream keeper's log")
                        .font(Theme.bodyFont(size: 18))
                        .foregroundColor(Theme.inkMuted)
                        .italic()
                }

                Spacer()

                // ── Login card ──
                VStack(spacing: 16) {
                    Button(action: { authManager.login() }) {
                        HStack(spacing: 10) {
                            if authManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.card))
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 20))
                                Text("Log In / Sign In")
                                    .font(Theme.bodyFont(size: 19))
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .foregroundColor(Theme.card)
                        .background(Theme.ink)
                        .cornerRadius(Theme.radiusMD)
                        .shadow(color: Theme.ink.opacity(0.2), radius: 6, x: 0, y: 3)
                    }
                    .disabled(authManager.isLoading)

                    if let errorMessage = authManager.loginError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 14))
                            Text(errorMessage)
                                .font(Theme.bodyFont(size: 14))
                        }
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text("stories that adapt to your child's sleep rhythm")
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .parchmentCard(cornerRadius: Theme.radiusLG)
                .padding(.horizontal, 28)
                .padding(.bottom, 60)
                .animation(.easeInOut(duration: 0.25), value: authManager.loginError)
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
