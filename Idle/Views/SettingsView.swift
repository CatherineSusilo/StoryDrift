import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var vitalsManager: VitalsManager
    @Binding var children: [ChildProfile]
    @Binding var selectedChild: ChildProfile?

    @State private var showingAddChild = false
    @State private var debugMode = false
    @State private var showAISettings = false
    @State private var showDrawingsManager = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    Text("settings")
                        .font(Theme.titleFont(size: 32))
                        .foregroundColor(Theme.ink)
                        .padding(.top, 20)

                    // ── Children ──
                    settingsSection(title: "children") {
                        ForEach(children) { child in
                            ChildSelectionCard(
                                child: child,
                                isSelected: selectedChild?.id == child.id,
                                onSelect: { selectedChild = child }
                            )
                        }
                        parchmentButton(icon: "plus.circle.fill", label: "add another child") {
                            showingAddChild = true
                        }
                    }

                    // ── Vitals Monitoring ──
                    settingsSection(title: "vitals monitoring") {
                        SettingsRow(icon: "heart.fill",    title: "auto-monitor",    subtitle: "start monitoring during stories",          toggle: .constant(true))
                        SettingsRow(icon: "moon.zzz.fill", title: "auto-end stories", subtitle: "stop when child is asleep (90% drift)", toggle: .constant(true))
                    }

                    // ── Audio ──
                    settingsSection(title: "audio") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("narration voice")
                                .font(Theme.bodyFont(size: 14))
                                .foregroundColor(Theme.inkMuted)
                            Menu {
                                ForEach(AudioService.availableVoices) { voice in
                                    Button(voice.name) {}
                                }
                            } label: {
                                HStack {
                                    Text("Sarah")
                                        .font(Theme.bodyFont(size: 16))
                                        .foregroundColor(Theme.ink)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(Theme.inkMuted)
                                }
                                .padding(12)
                                .background(Theme.background)
                                .cornerRadius(Theme.radiusSM)
                                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1.5))
                            }
                        }
                    }

                    // ── AI & Drawings ──
                    settingsSection(title: "ai & drawings") {
                        parchmentNavRow(icon: "paintpalette.fill", label: "ai customization")   { showAISettings = true }
                        parchmentNavRow(icon: "photo.on.rectangle.angled", label: "drawings collection") { showDrawingsManager = true }
                    }

                    // ── Advanced ──
                    settingsSection(title: "advanced") {
                        SettingsRow(icon: "ladybug.fill", title: "debug mode", subtitle: "show technical information", toggle: $debugMode)
                        if debugMode {
                            VStack(alignment: .leading, spacing: 8) {
                                DebugInfoRow(label: "heart rate",    value: "\(Int(vitalsManager.currentHeartRate)) bpm")
                                DebugInfoRow(label: "breathing",     value: String(format: "%.1f rpm", vitalsManager.currentBreathingRate))
                                DebugInfoRow(label: "signal quality",value: "\(vitalsManager.signalQuality)%")
                                DebugInfoRow(label: "drift score",   value: "\(Int(vitalsManager.driftScore))%")
                            }
                            .padding(12)
                            .background(Theme.background)
                            .cornerRadius(Theme.radiusSM)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1))
                        }
                    }

                    // ── About ──
                    VStack(spacing: 10) {
                        Image("StoryDriftLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                        Text("Version 1.0.0")
                            .font(Theme.bodyFont(size: 14))
                            .foregroundColor(Theme.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)

                    // ── Sign out ──
                    Button(action: { authManager.logout() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("sign out")
                                .fontWeight(.semibold)
                        }
                        .font(Theme.bodyFont(size: 17))
                        .foregroundColor(Theme.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(Theme.destructive.opacity(0.08))
                        .cornerRadius(Theme.radiusMD)
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMD).stroke(Theme.destructive.opacity(0.25), lineWidth: 1.5))
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingAddChild) {
            ChildOnboardingView { child in
                children.append(child)
                showingAddChild = false
            }
        }
        .fullScreenCover(isPresented: $showAISettings) {
            AISettingsView(onBack: { showAISettings = false })
                .environmentObject(authManager)
        }
        .fullScreenCover(isPresented: $showDrawingsManager) {
            DrawingsManagerView(onBack: { showDrawingsManager = false })
                .environmentObject(authManager)
        }
    }

    // MARK: - Helpers
    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(Theme.titleFont(size: 20))
                .foregroundColor(Theme.ink)
            content()
        }
        .padding(16)
        .parchmentCard(cornerRadius: Theme.radiusMD)
    }

    @ViewBuilder
    private func parchmentButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label)
                    .fontWeight(.semibold)
            }
            .font(Theme.bodyFont(size: 16))
            .foregroundColor(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Theme.accent.opacity(0.3))
            .cornerRadius(Theme.radiusSM)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private func parchmentNavRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(Theme.inkMuted)
                    .frame(width: 28)
                Text(label)
                    .font(Theme.bodyFont(size: 16))
                    .foregroundColor(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.inkMuted)
            }
            .padding(14)
            .background(Theme.background)
            .cornerRadius(Theme.radiusSM)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1))
        }
    }
}

// MARK: - ChildSelectionCard
struct ChildSelectionCard: View {
    let child: ChildProfile
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(child.name)
                        .font(Theme.bodyFont(size: 17))
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.ink)
                    Text("age \(child.age)")
                        .font(Theme.bodyFont(size: 13))
                        .foregroundColor(Theme.inkMuted)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.success)
                        .font(.system(size: 22))
                }
            }
            .padding(14)
            .background(isSelected ? Theme.accent.opacity(0.25) : Theme.background)
            .cornerRadius(Theme.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .stroke(isSelected ? Theme.borderActive : Theme.border, lineWidth: isSelected ? 2 : 1.5)
            )
        }
    }
}

// MARK: - SettingsRow
struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var toggle: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Theme.inkMuted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.bodyFont(size: 16))
                    .foregroundColor(Theme.ink)
                Text(subtitle)
                    .font(Theme.bodyFont(size: 12))
                    .foregroundColor(Theme.inkMuted)
            }
            Spacer()
            Toggle("", isOn: $toggle)
                .tint(Theme.ink)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - DebugInfoRow
struct DebugInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont(size: 13))
                .foregroundColor(Theme.inkMuted)
            Spacer()
            Text(value)
                .font(Theme.bodyFont(size: 13))
                .fontWeight(.bold)
                .foregroundColor(Theme.ink)
        }
    }
}

#Preview {
    SettingsView(
        children: .constant([
            Child(id: "1", userId: "user1", name: "Emma", age: 5,
                  dateOfBirth: nil, avatar: nil,
                  createdAt: Date(), updatedAt: Date(), preferences: nil)
        ]),
        selectedChild: .constant(nil)
    )
    .environmentObject(AuthManager())
    .environmentObject(VitalsManager())
}
