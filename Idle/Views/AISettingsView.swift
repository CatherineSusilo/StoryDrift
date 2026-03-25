import SwiftUI

/// Ported from AISettings.tsx — lets the parent customize image style, story tone, and narration voice.
struct AISettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    let onBack: () -> Void

    // MARK: - Tabs
    enum SettingsTab: String, CaseIterable {
        case image = "Image Style"
        case text  = "Story Tone"
        case voice = "Voice"
    }

    @State private var activeTab: SettingsTab = .image

    // MARK: - Image Style
    @State private var imageStyle: String = UserDefaults.standard.string(forKey: "ai_image_style") ?? "soft watercolor"
    @State private var imageSaved = false

    // MARK: - Text Tone
    @State private var textTone: String  = UserDefaults.standard.string(forKey: "ai_text_tone") ?? "gentle and calming"
    @State private var toneSaved = false

    // MARK: - Voice
    @State private var voices: [ElevenLabsVoice] = []
    @State private var selectedVoiceId: String? = UserDefaults.standard.string(forKey: "ai_selected_voice")
    @State private var voicesLoading = false

    // MARK: - Parchment palette (mirrors the web app's warm sepia theme)
    private let bg         = Color(red: 0.894, green: 0.835, blue: 0.718)
    private let cardBg     = Color(red: 0.980, green: 0.961, blue: 0.922)
    private let borderClr  = Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.28)
    private let activeTabBg = Color(red: 0.824, green: 0.706, blue: 0.549).opacity(0.4)
    private let btnBg      = Color(red: 0.824, green: 0.706, blue: 0.549).opacity(0.5)
    private let ink        = Color(red: 0.078, green: 0.059, blue: 0.039)

    @EnvironmentObject var vitalsManager: VitalsManager

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Camera toggle
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $vitalsManager.isCameraEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Biometric Camera", systemImage: "camera.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ink)
                                Text(vitalsManager.isCameraEnabled
                                     ? "Pulse & breathing tracked — story adapts in real time"
                                     : "Camera off — story adapts from session time & child profile")
                                    .font(.system(size: 12))
                                    .foregroundColor(ink.opacity(0.6))
                            }
                        }
                        .tint(Color(red: 0.3, green: 0.6, blue: 0.3))
                        .padding(14)
                        .background(cardBg)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderClr, lineWidth: 1))
                    }
                    .padding(.top, 8)

                    // MARK: Header
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(ink)
                        }
                        Spacer()
                        Text("ai customization")
                            .font(.custom("IndieFlower-Regular", size: 30))
                            .foregroundColor(ink)
                        Spacer()
                        Color.clear.frame(width: 24) // balance chevron
                    }
                    .padding(.top, 20)

                    // MARK: Tab Row
                    HStack(spacing: 10) {
                        ForEach(SettingsTab.allCases, id: \.self) { tab in
                            tabButton(tab)
                        }
                    }

                    // MARK: Tab Content
                    switch activeTab {
                    case .image: imageStylePanel
                    case .text:  textTonePanel
                    case .voice: voicePanel
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationBarHidden(true)
        .task { await loadVoices() }
    }

    // MARK: - Tab Button
    @ViewBuilder
    private func tabButton(_ tab: SettingsTab) -> some View {
        let isActive = activeTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tabIcon(tab))
                    .font(.system(size: 14))
                Text(tab.rawValue)
                    .font(.custom("PatrickHand-Regular", size: 16))
                    .fontWeight(isActive ? .bold : .regular)
            }
            .foregroundColor(isActive ? ink : ink.opacity(0.65))
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(isActive ? activeTabBg : cardBg.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? borderClr.opacity(1.4) : borderClr.opacity(0.5),
                            lineWidth: isActive ? 2 : 1)
            )
            .cornerRadius(6)
        }
    }

    private func tabIcon(_ tab: SettingsTab) -> String {
        switch tab {
        case .image: return "paintpalette"
        case .text:  return "textformat"
        case .voice: return "mic"
        }
    }

    // MARK: - Image Style Panel
    private var imageStylePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            parchmentCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("image generation style")
                        .font(.custom("PatrickHand-Regular", size: 22))
                        .fontWeight(.bold)
                        .foregroundColor(ink)
                    Text("describe how you want story images to look")
                        .font(.custom("PatrickHand-Regular", size: 15))
                        .foregroundColor(ink.opacity(0.65))

                    TextEditor(text: $imageStyle)
                        .font(.custom("PatrickHand-Regular", size: 16))
                        .foregroundColor(ink)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 100)
                        .background(Color.white.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(borderClr, lineWidth: 1.5)
                        )
                        .cornerRadius(6)

                    saveButton(label: "save style", saved: imageSaved) {
                        UserDefaults.standard.set(imageStyle, forKey: "ai_image_style")
                        showSaved($imageSaved)
                    }
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: - Text Tone Panel
    private var textTonePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            parchmentCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("storytelling tone")
                        .font(.custom("PatrickHand-Regular", size: 22))
                        .fontWeight(.bold)
                        .foregroundColor(ink)
                    Text("customize the narrative voice and pacing")
                        .font(.custom("PatrickHand-Regular", size: 15))
                        .foregroundColor(ink.opacity(0.65))

                    TextEditor(text: $textTone)
                        .font(.custom("PatrickHand-Regular", size: 16))
                        .foregroundColor(ink)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 100)
                        .background(Color.white.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(borderClr, lineWidth: 1.5)
                        )
                        .cornerRadius(6)

                    saveButton(label: "save tone", saved: toneSaved) {
                        UserDefaults.standard.set(textTone, forKey: "ai_text_tone")
                        showSaved($toneSaved)
                    }
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: - Voice Panel
    private var voicePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Upload hint card (voice cloning is a backend feature)
            parchmentCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("upload your voice")
                        .font(.custom("PatrickHand-Regular", size: 22))
                        .fontWeight(.bold)
                        .foregroundColor(ink)
                    Text("upload 2–3 audio clips of you reading (at least 30 seconds each) to create an AI clone of your voice")
                        .font(.custom("PatrickHand-Regular", size: 15))
                        .foregroundColor(ink.opacity(0.65))

                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                        Text("voice upload coming soon")
                            .fontWeight(.bold)
                    }
                    .font(.custom("PatrickHand-Regular", size: 16))
                    .foregroundColor(ink.opacity(0.7))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(btnBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderClr, lineWidth: 2)
                    )
                    .cornerRadius(6)
                }
            }

            // Available voices
            parchmentCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("available voices")
                        .font(.custom("PatrickHand-Regular", size: 22))
                        .fontWeight(.bold)
                        .foregroundColor(ink)

                    if voicesLoading {
                        HStack {
                            ProgressView()
                                .tint(ink)
                            Text("loading voices…")
                                .font(.custom("PatrickHand-Regular", size: 15))
                                .foregroundColor(ink.opacity(0.6))
                        }
                    } else if voices.isEmpty {
                        Text("no voices found")
                            .font(.custom("PatrickHand-Regular", size: 15))
                            .foregroundColor(ink.opacity(0.55))
                    } else {
                        ForEach(voices) { voice in
                            voiceRow(voice)
                        }
                    }
                }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func voiceRow(_ voice: ElevenLabsVoice) -> some View {
        let isSelected = selectedVoiceId == voice.voiceId
        Button {
            selectedVoiceId = voice.voiceId
            UserDefaults.standard.set(voice.voiceId, forKey: "ai_selected_voice")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2")
                    .foregroundColor(ink.opacity(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                        .fontWeight(.bold)
                        .foregroundColor(ink)
                    if let labels = voice.labels, !labels.isEmpty {
                        Text(labels.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
                            .font(.system(size: 13))
                            .foregroundColor(ink.opacity(0.5))
                    }
                }
                Spacer()
                if isSelected {
                    Text("active")
                        .font(.custom("PatrickHand-Regular", size: 13))
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.16, green: 0.23, blue: 0.16).opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(4)
                }
            }
            .font(.custom("PatrickHand-Regular", size: 16))
            .padding(14)
            .background(isSelected ? activeTabBg : cardBg.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? borderClr : borderClr.opacity(0.5),
                            lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(6)
        }
    }

    // MARK: - Shared UI helpers
    @ViewBuilder
    private func parchmentCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(20)
        .background(cardBg.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderClr, lineWidth: 2)
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 3)
    }

    @ViewBuilder
    private func saveButton(label: String, saved: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(saved ? "saved ✓" : label)
                .font(.custom("PatrickHand-Regular", size: 17))
                .fontWeight(.bold)
                .foregroundColor(ink.opacity(0.85))
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(btnBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderClr, lineWidth: 2)
                )
                .cornerRadius(6)
        }
        .animation(.easeInOut(duration: 0.2), value: saved)
    }

    // MARK: - Helpers
    private func showSaved(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { flag.wrappedValue = false }
    }

    private func loadVoices() async {
        guard let token = authManager.accessToken else { return }
        voicesLoading = true
        defer { voicesLoading = false }
        do {
            let response: ElevenLabsVoicesResponse = try await APIService.shared.request(
                endpoint: "/api/voices",
                token: token
            )
            await MainActor.run {
                voices = response.voices ?? []
            }
        } catch {
            print("AISettingsView: failed to load voices — \(error)")
        }
    }
}

// MARK: - ElevenLabs voice models (mirrors backend /api/voices response)
struct ElevenLabsVoicesResponse: Decodable {
    let voices: [ElevenLabsVoice]?
}

struct ElevenLabsVoice: Decodable, Identifiable {
    let voiceId: String
    let name: String
    let labels: [String: String]?

    var id: String { voiceId }

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name, labels
    }
}

#Preview {
    AISettingsView(onBack: {})
        .environmentObject(AuthManager())
}
