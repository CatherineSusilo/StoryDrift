import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var eyeTracking: EyeTrackingManager
    @Binding var children: [ChildProfile]
    @Binding var selectedChild: ChildProfile?

    @ObservedObject private var gateManager = ParentalGateManager.shared

    @State private var showingAddChild = false
    @State private var showAISettings = false
    @State private var showResetPasscode = false   // reset passcode sheet

    // Account deletion (PIPEDA / Quebec Law 25)
    @State private var isDeletingAccount = false
    @State private var showDeleteAccountConfirm = false
    @State private var showDeleteAccountError = false

    // Single-child deletion (PIPEDA / Quebec Law 25)
    @State private var childToDelete: ChildProfile?
    @State private var isDeletingChild = false
    @State private var showDeleteChildError = false

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
                            HStack(spacing: 10) {
                                ChildSelectionCard(
                                    child: child,
                                    isSelected: selectedChild?.id == child.id,
                                    onSelect: { selectedChild = child }
                                )
                                // Delete is parent-only
                                if gateManager.isParentMode {
                                    Button {
                                        childToDelete = child
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 18))
                                            .foregroundColor(Theme.destructive)
                                            .frame(width: 48, height: 48)
                                            .background(Theme.background)
                                            .cornerRadius(Theme.radiusSM)
                                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1))
                                    }
                                    .disabled(isDeletingChild)
                                }
                            }
                        }
                        parchmentButton(icon: "plus.circle.fill", label: "add another child") {
                            showingAddChild = true
                        }
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
                    }

                    // ── Parental Controls ──
                    settingsSection(title: "parental controls") {
                        // Current mode badge
                        HStack(spacing: 10) {
                            Image(systemName: gateManager.isParentMode ? "lock.open.fill" : "lock.fill")
                                .font(.system(size: 18))
                                .foregroundColor(gateManager.isParentMode ? Theme.success : Theme.inkMuted)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gateManager.isParentMode ? "parent mode" : "child mode")
                                    .font(Theme.bodyFont(size: 16))
                                    .foregroundColor(Theme.ink)
                                Text(gateManager.isParentMode ? "full access enabled" : "limited access")
                                    .font(Theme.bodyFont(size: 12))
                                    .foregroundColor(Theme.inkMuted)
                            }
                            Spacer()
                            // Mode toggle button
                            Button {
                                if gateManager.isParentMode {
                                    gateManager.enterChildMode()
                                }
                                // Switching TO parent mode is handled via settings gate (already unlocked since we're in settings)
                            } label: {
                                Text(gateManager.isParentMode ? "switch to child" : "in parent mode")
                                    .font(Theme.bodyFont(size: 13))
                                    .foregroundColor(gateManager.isParentMode ? Theme.destructive : Theme.success)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        (gateManager.isParentMode ? Theme.destructive : Theme.success).opacity(0.12)
                                    )
                                    .cornerRadius(Theme.radiusSM)
                            }
                            .disabled(!gateManager.isParentMode)
                        }
                        .padding(.vertical, 4)

                        Divider().background(Theme.border)

                        // Reset passcode
                        parchmentNavRow(icon: "key.fill", label: "reset passcode") {
                            showResetPasscode = true
                        }
                    }

                    // ── Data & privacy ──
                    settingsSection(title: "data & privacy") {
                        Button {
                            showDeleteAccountConfirm = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.system(size: 18))
                                    .foregroundColor(Theme.destructive)
                                    .frame(width: 28)
                                Text("Delete my account")
                                    .font(Theme.bodyFont(size: 16))
                                    .foregroundColor(Theme.destructive)
                                Spacer()
                                if isDeletingAccount {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.inkMuted)
                                }
                            }
                            .padding(14)
                            .background(Theme.background)
                            .cornerRadius(Theme.radiusSM)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1))
                        }
                        .disabled(isDeletingAccount)
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

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingAddChild) {
            // Parent already has an account/passcode here, so allow reusing it.
            ChildOnboardingView(allowUseExisting: true) { child in
                children.append(child)
                showingAddChild = false
            }
        }
        .fullScreenCover(isPresented: $showAISettings) {
            AISettingsView(onBack: { showAISettings = false })
                .environmentObject(authManager)
        }
        .fullScreenCover(isPresented: $showResetPasscode) {
            PasscodeEntryView(mode: .reset, title: "reset passcode") { newPin in
                gateManager.resetPasscode(newPin: newPin, token: authManager.accessToken)
                showResetPasscode = false
            } onCancel: {
                showResetPasscode = false
            }
            .environmentObject(authManager)
        }
        .confirmationDialog("Delete account?", isPresented: $showDeleteAccountConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, all child profiles, all stories, and all audio and images. This cannot be undone.")
        }
        .alert("Something went wrong", isPresented: $showDeleteAccountError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again or contact support@storydrift.app.")
        }
        .confirmationDialog("Delete child?", isPresented: Binding(
            get: { childToDelete != nil },
            set: { if !$0 { childToDelete = nil } }
        ), titleVisibility: .visible, presenting: childToDelete) { child in
            Button("Delete", role: .destructive) {
                Task { await deleteChild(child) }
            }
            Button("Cancel", role: .cancel) { childToDelete = nil }
        } message: { child in
            Text("This permanently deletes \(child.name)'s profile, all their stories, and all audio and images. This cannot be undone.")
        }
        .alert("Something went wrong", isPresented: $showDeleteChildError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again or contact support@storydrift.app.")
        }
    }

    // MARK: - Child deletion
    private func deleteChild(_ child: ChildProfile) async {
        isDeletingChild = true
        let token = authManager.accessToken
            ?? UserDefaults.standard.string(forKey: "accessToken") ?? ""
        do {
            try await APIService.shared.deleteChild(childId: child.id, token: token)
            children.removeAll { $0.id == child.id }
            if selectedChild?.id == child.id {
                selectedChild = children.first
            }
            childToDelete = nil
        } catch {
            print("❌ Child deletion failed: \(error)")
            showDeleteChildError = true
        }
        isDeletingChild = false
    }

    // MARK: - Account deletion
    private func deleteAccount() async {
        isDeletingAccount = true
        let token = authManager.accessToken
            ?? UserDefaults.standard.string(forKey: "accessToken") ?? ""
        do {
            try await APIService.shared.deleteAccount(token: token)
            authManager.logout()
        } catch {
            print("❌ Account deletion failed: \(error)")
            showDeleteAccountError = true
        }
        isDeletingAccount = false
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
    .environmentObject(EyeTrackingManager.shared)
}
