import SwiftUI

/// Full-screen consent sheet shown to the parent on first launch, before any
/// other app content is accessible. PIPEDA / Quebec Law 25 compliance.
struct PrivacyConsentView: View {
    let onConsented: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // ── Header ──
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Before you begin")
                            .font(Theme.titleFont(size: 34))
                            .foregroundColor(Theme.ink)

                        Text("StoryDrift is designed for parents. Please read how we handle your family's data.")
                            .font(Theme.bodyFont(size: 16))
                            .foregroundColor(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 16)

                    // ── Rows ──
                    VStack(alignment: .leading, spacing: 22) {
                        consentRow(
                            icon: "person.crop.circle",
                            heading: "What we collect",
                            body: "Your child's name and age, stories generated in the app, and drawings your child creates during storytime."
                        )
                        consentRow(
                            icon: "building.2",
                            heading: "Who processes your data",
                            body: "Stories and drawings are processed by Anthropic (AI), ElevenLabs (narration), and fal.ai (illustrations). Audio and images are stored on Cloudflare. Your data is never sold."
                        )
                        consentRow(
                            icon: "trash",
                            heading: "Your right to delete",
                            body: "You can permanently delete your account and all associated data at any time from the Settings screen."
                        )
                    }

                    // ── Privacy policy link ──
                    Button {
                        if let url = URL(string: "https://storydrift.app/privacy") {
                            openURL(url)
                        }
                    } label: {
                        Text("Read our full Privacy Policy")
                            .font(Theme.bodyFont(size: 15))
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.accent)
                            .underline()
                    }

                    Spacer(minLength: 24)

                    // ── Primary action ──
                    Button(action: agree) {
                        Text("I understand and agree")
                            .font(Theme.bodyFont(size: 18))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent)
                            .cornerRadius(Theme.radiusMD)
                    }
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Row
    @ViewBuilder
    private func consentRow(icon: String, heading: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(Theme.accent)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(Theme.bodyFont(size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.ink)
                Text(body)
                    .font(Theme.bodyFont(size: 15))
                    .foregroundColor(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Action
    private func agree() {
        // Fire-and-forget — never block the UI on the network. The UserDefaults
        // flag below is the source of truth even if the network is unavailable.
        Task { try? await APIService.shared.recordConsent(version: "1.0") }
        UserDefaults.standard.set(true, forKey: "consentGranted")
        UserDefaults.standard.set("1.0", forKey: "consentVersion")
        onConsented()
    }
}

#Preview {
    PrivacyConsentView(onConsented: {})
}
