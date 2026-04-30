import SwiftUI

/// A full-screen 6-digit PIN pad.
///
/// Modes:
///  - `.unlock`        — verify existing passcode → call onSuccess
///  - `.setup`         — enter new PIN twice → call onSuccess(pin)
///  - `.reset`         — verify old PIN first, then set new one
///
enum PasscodeEntryMode {
    case unlock
    case setup
    case reset
}

struct PasscodeEntryView: View {
    let mode: PasscodeEntryMode
    let title: String
    var subtitle: String = ""
    /// Called when the user enters the correct / confirmed PIN.
    /// For `.unlock` the pin string is the entered value.
    /// For `.setup` / `.reset` the pin string is the new PIN.
    var onSuccess: (String) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var authManager: AuthManager
    @StateObject private var gate = ParentalGateManager.shared
    @State private var entered: String = ""
    @State private var firstEntry: String = ""
    @State private var phase: Phase = .enter
    @State private var errorMessage: String = ""
    @State private var shakeOffset: CGFloat = 0
    @State private var isVerifying = false
    @State private var showForgotAlert = false
    @State private var isResetting = false
    @State private var resetSuccess = false

    private enum Phase { case enterOld, enter, confirm }

    // Derived prompt
    private var prompt: String {
        switch (mode, phase) {
        case (.unlock, _):    return title
        case (.setup, .enter):    return "create a 6-digit passcode"
        case (.setup, .confirm):  return "confirm your passcode"
        case (.reset, .enterOld): return "enter your current passcode"
        case (.reset, .enter):    return "enter your new passcode"
        case (.reset, .confirm):  return "confirm your new passcode"
        default: return title
        }
    }

    var body: some View {
        ZStack {
            // Dark dreamy background
            LinearGradient(
                colors: [Color(red:0.04,green:0.04,blue:0.14), Color(red:0.12,green:0.04,blue:0.22)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────────────────
                HStack {
                    Button(action: onCancel) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                            Text("cancel")
                                .font(Theme.bodyFont(size: 15))
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .padding(12)
                    }
                    Spacer()
                }
                .padding(.top, 8)

                Spacer()

                // ── Lock icon ────────────────────────────────────────────────
                Image(systemName: mode == .unlock ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 16)

                // ── Prompt ───────────────────────────────────────────────────
                Text(prompt)
                    .font(Theme.titleFont(size: 24))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if !subtitle.isEmpty && phase == .enter && mode == .unlock {
                    Text(subtitle)
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.top, 4)
                }

                // ── Error ────────────────────────────────────────────────────
                Text(errorMessage)
                    .font(Theme.bodyFont(size: 14))
                    .foregroundColor(Color(red:1,green:0.4,blue:0.4))
                    .padding(.top, 6)
                    .frame(height: 20)
                    .opacity(errorMessage.isEmpty ? 0 : 1)

                // ── Dots ─────────────────────────────────────────────────────
                if isVerifying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                        .padding(.top, 28)
                        .padding(.bottom, 40)
                } else {
                HStack(spacing: 16) {
                    ForEach(0..<6, id: \.self) { i in
                        Circle()
                            .fill(i < entered.count ? Color.white : Color.white.opacity(0.2))
                            .frame(width: 14, height: 14)
                            .scaleEffect(i < entered.count ? 1.1 : 1.0)
                            .animation(.spring(response: 0.2), value: entered.count)
                    }
                }
                .offset(x: shakeOffset)
                .padding(.top, 28)
                .padding(.bottom, 40)
                } // end else isVerifying

                // ── Keypad ───────────────────────────────────────────────────
                VStack(spacing: 14) {
                    ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                        HStack(spacing: 24) {
                            ForEach(row, id: \.self) { digit in
                                keyButton(label: "\(digit)")
                            }
                        }
                    }
                    HStack(spacing: 24) {
                        // Empty slot
                        Color.clear.frame(width: 72, height: 72)
                        keyButton(label: "0")
                        // Backspace
                        Button(action: backspace) {
                            Image(systemName: "delete.left.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(width: 72, height: 72)
                        }
                    }
                }

                // ── Forgot passcode (unlock mode only) ───────────────────────
                if mode == .unlock {
                    if resetSuccess {
                        Text("✅ passcode reset to 000000")
                            .font(Theme.bodyFont(size: 14))
                            .foregroundColor(.green.opacity(0.9))
                            .padding(.top, 20)
                    } else if isResetting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                            .padding(.top, 20)
                    } else {
                        Button("forgot passcode?") {
                            showForgotAlert = true
                        }
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.top, 20)
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            if mode == .reset { phase = .enterOld }
            else if mode == .setup { phase = .enter }
            else { phase = .enter }
        }
        .alert("forgot passcode?", isPresented: $showForgotAlert) {
            Button("verify with account", role: .destructive) { doForgotReset() }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("You'll be asked to sign in to your account to verify your identity. Your passcode will then be reset to 000000.")
        }
    }

    // MARK: - Key button
    private func keyButton(label: String) -> some View {
        Button(action: { append(label) }) {
            Text(label)
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    // MARK: - Input logic
    private func append(_ digit: String) {
        guard entered.count < 6, !isVerifying else { return }
        entered += digit
        errorMessage = ""
        if entered.count == 6 { handleComplete() }
    }

    private func backspace() {
        guard !entered.isEmpty, !isVerifying else { return }
        entered.removeLast()
        errorMessage = ""
    }

    private func handleComplete() {
        switch mode {
        case .unlock:
            verifyPin(entered) { valid in
                if valid { onSuccess(self.entered) }
                else { shake(); errorMessage = "incorrect passcode"; entered = "" }
            }

        case .setup:
            if phase == .enter {
                firstEntry = entered; entered = ""; phase = .confirm
            } else {
                if entered == firstEntry { onSuccess(entered) }
                else { shake(); errorMessage = "passcodes don't match — try again"; entered = ""; firstEntry = ""; phase = .enter }
            }

        case .reset:
            if phase == .enterOld {
                verifyPin(entered) { valid in
                    if valid { entered = ""; phase = .enter }
                    else { shake(); errorMessage = "incorrect passcode"; entered = "" }
                }
            } else if phase == .enter {
                firstEntry = entered; entered = ""; phase = .confirm
            } else {
                if entered == firstEntry { onSuccess(entered) }
                else { shake(); errorMessage = "passcodes don't match — try again"; entered = ""; firstEntry = ""; phase = .enter }
            }
        }
    }

    /// Verify pin — uses backend if token available, falls back to local.
    private func verifyPin(_ pin: String, completion: @escaping (Bool) -> Void) {
        if let token = authManager.accessToken {
            isVerifying = true
            errorMessage = ""
            Task {
                let valid = await gate.verifyWithBackend(pin: pin, token: token)
                await MainActor.run { isVerifying = false; completion(valid) }
            }
        } else {
            completion(gate.verify(pin))
        }
    }

    /// Triggers Auth0 re-authentication to verify identity, then resets passcode to 000000.
    private func doForgotReset() {
        isResetting = true
        authManager.reauthenticate { success in
            guard success else {
                isResetting = false
                errorMessage = "verification cancelled"
                return
            }
            let token = authManager.accessToken
            gate.resetPasscode(newPin: "000000", token: token)
            Task {
                if let token { await gate.syncPasscodeToBackendPublic(pin: "000000", token: token) }
                await MainActor.run {
                    isResetting = false
                    resetSuccess = true
                    entered = ""
                    errorMessage = ""
                }
            }
        }
    }

    private func shake() {
        let k: CGFloat = 10
        withAnimation(.default) { shakeOffset = k }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = -k }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = k * 0.5 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.default) { shakeOffset = 0 }
        }
    }
}

#Preview {
    PasscodeEntryView(mode: .unlock, title: "parent access", onSuccess: { _ in }, onCancel: {})
        .environmentObject(AuthManager())
}
