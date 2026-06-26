import SwiftUI

struct ChildOnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var currentStep = 0
    @State private var childName = ""
    @State private var childAge = 5
    @State private var selectedTone: StorytellingTone = .calming
    @State private var parentPrompt = ""
    @State private var selectedState: InitialState = .normal
    @State private var passcode = ""          // set during step 4
    @State private var passcodeConfirm = ""
    @State private var passcodeError = ""
    @State private var useExistingPasscode = false   // reuse current parental passcode
    @State private var isCreating = false

    private let totalSteps = 5   // 0-4

    /// When false (first account creation) the "use my current passcode"
    /// shortcut is hidden — a brand-new account has no passcode to reuse.
    var allowUseExisting: Bool = false

    let onComplete: (ChildProfile) -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Progress indicator — now 5 steps
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index <= currentStep ? Theme.accent : Theme.border)
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                ScrollView {
                    VStack(spacing: 32) {
                        switch currentStep {
                        case 0: Step1View(name: $childName, age: $childAge)
                        case 1: Step2View(tone: $selectedTone)
                        case 2: Step3View(prompt: $parentPrompt)
                        case 3: Step4View(state: $selectedState)
                        case 4: PasscodeSetupStepView(
                                    passcode: $passcode,
                                    confirm: $passcodeConfirm,
                                    errorMessage: $passcodeError,
                                    useExisting: $useExistingPasscode,
                                    allowUseExisting: allowUseExisting)
                        default: EmptyView()
                        }
                    }
                    .padding()
                }

                // Navigation buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        Button {
                            withAnimation { currentStep -= 1 }
                        } label: {
                            Text("Back")
                                .font(Theme.bodyFont(size: 17))
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Theme.card)
                                .cornerRadius(Theme.radiusLG)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusLG)
                                        .stroke(Theme.border, lineWidth: 1.5)
                                )
                                .contentShape(Rectangle())
                        }
                    }

                    Button {
                        if currentStep == totalSteps - 1 {
                            if useExistingPasscode {
                                createChild()
                            } else {
                                guard validatePasscode() else { return }
                                createChild()
                            }
                        } else {
                            withAnimation { currentStep += 1 }
                        }
                    } label: {
                        Text(currentStep == totalSteps - 1 ? "Create Profile" : "Next")
                            .font(Theme.bodyFont(size: 17))
                            .fontWeight(.bold)
                            .foregroundColor(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Theme.accent)
                            .cornerRadius(Theme.radiusLG)
                            .opacity((isCreating || !canProceed) ? 0.5 : 1)
                            .contentShape(Rectangle())
                    }
                    .disabled(isCreating || !canProceed)
                }
                .padding()
            }
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case 0: return !childName.isEmpty && childAge >= 2 && childAge <= 12
        case 2: return !parentPrompt.isEmpty
        case 4: return useExistingPasscode || (passcode.count == 6 && passcodeConfirm.count == 6)
        default: return true
        }
    }

    private func validatePasscode() -> Bool {
        if passcode != passcodeConfirm {
            passcodeError = "passcodes don't match"
            return false
        }
        passcodeError = ""
        return true
    }

    private func createChild() {
        guard let token = authManager.accessToken else { return }
        isCreating = true

        let request = CreateChildRequest(
            name: childName,
            age: childAge,
            dateOfBirth: nil,
            avatar: nil,
            preferences: ChildPrefsRequest(
                storytellingTone: selectedTone.rawValue,
                favoriteThemes: [],
                defaultInitialState: "normal",
                personality: parentPrompt.isEmpty ? nil : parentPrompt,
                favoriteMedia: nil,
                parentGoals: nil
            )
        )

        Task {
            do {
                let createdChild = try await APIService.shared.createChild(request: request, token: token)
                DispatchQueue.main.async {
                    // Only overwrite the parental passcode when the parent set a new
                    // one; otherwise keep their existing passcode unchanged. Either
                    // way, land the parent in parent mode after creating a profile.
                    if self.useExistingPasscode {
                        ParentalGateManager.shared.enterParentMode()
                    } else {
                        ParentalGateManager.shared.setPasscode(self.passcode, token: self.authManager.accessToken)
                    }
                    self.onComplete(createdChild)
                    self.dismiss()
                }
            } catch {
                print("Error creating child: \(error)")
                DispatchQueue.main.async { self.isCreating = false }
            }
        }
    }
}

// MARK: - Onboarding Steps

struct Step1View: View {
    @Binding var name: String
    @Binding var age: Int

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.accent)

            Text("Let's create a profile")
                .font(Theme.titleFont(size: 28))
                .foregroundColor(Theme.ink)

            Text("Tell us about your child")
                .font(Theme.bodyFont(size: 16))
                .foregroundColor(Theme.inkMuted)

            VStack(alignment: .leading, spacing: 16) {
                Text("Child's Name")
                    .font(Theme.bodyFont(size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(Theme.inkMuted)

                TextField("Enter name", text: $name)
                    .textFieldStyle(CustomTextFieldStyle())

                Text("Age")
                    .font(Theme.bodyFont(size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(Theme.inkMuted)
                    .padding(.top, 8)

                Picker("Age", selection: $age) {
                    ForEach(2...12, id: \.self) { age in
                        Text("\(age) years old")
                            .font(Theme.bodyFont(size: 20))
                            .foregroundColor(Theme.ink)
                            .tag(age)
                    }
                }
                .pickerStyle(.wheel)
                .tint(Theme.ink)
                .frame(height: 120)
            }
            .padding(.top, 16)
        }
    }
}

struct Step2View: View {
    @Binding var tone: StorytellingTone

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "theatermasks.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.accent)

            Text("Choose a Tone")
                .font(Theme.titleFont(size: 28))
                .foregroundColor(Theme.ink)

            Text("What storytelling style does your child prefer?")
                .font(Theme.bodyFont(size: 16))
                .foregroundColor(Theme.inkMuted)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(StorytellingTone.allCases, id: \.self) { toneOption in
                    ToneOptionView(
                        tone: toneOption,
                        isSelected: tone == toneOption
                    ) {
                        tone = toneOption
                    }
                }
            }
            .padding(.top, 16)
        }
    }
}

struct ToneOptionView: View {
    let tone: StorytellingTone
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(tone.emoji)
                    .font(.system(size: 32))

                VStack(alignment: .leading, spacing: 4) {
                    Text(tone.displayName)
                        .font(Theme.bodyFont(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.ink)

                    Text(tone.rawValue.capitalized)
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(Theme.inkMuted)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.accent)
                        .font(.system(size: 24))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .fill(isSelected ? Theme.accent.opacity(0.25) : Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .stroke(
                                isSelected ? Theme.borderActive : Theme.border,
                                lineWidth: 1.5
                            )
                    )
            )
            .contentShape(Rectangle())
        }
    }
}

struct Step3View: View {
    @Binding var prompt: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(Theme.accent)

            Text("Personalize Stories")
                .font(Theme.titleFont(size: 28))
                .foregroundColor(Theme.ink)

            Text("Tell us about your child's interests, favorite characters, or anything special")
                .font(Theme.bodyFont(size: 16))
                .foregroundColor(Theme.inkMuted)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Parent Prompt")
                    .font(Theme.bodyFont(size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(Theme.inkMuted)

                TextEditor(text: $prompt)
                    .frame(height: 150)
                    .padding()
                    .background(Theme.card)
                    .cornerRadius(Theme.radiusMD)
                    .foregroundColor(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .stroke(Theme.border, lineWidth: 1.5)
                    )

                Text("Example: Loves unicorns, enjoys space adventures, has a teddy bear named Mr. Snuggles")
                    .font(Theme.bodyFont(size: 12))
                    .foregroundColor(Theme.inkFaint)
                    .italic()
            }
            .padding(.top, 16)
        }
    }
}

struct Step4View: View {
    @Binding var state: InitialState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.accent)

            Text("Initial State")
                .font(Theme.titleFont(size: 28))
                .foregroundColor(Theme.ink)

            Text("How energetic is your child typically at bedtime?")
                .font(Theme.bodyFont(size: 16))
                .foregroundColor(Theme.inkMuted)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(InitialState.allCases, id: \.self) { stateOption in
                    StateOptionView(
                        state: stateOption,
                        isSelected: state == stateOption
                    ) {
                        state = stateOption
                    }
                }
            }
            .padding(.top, 16)
        }
    }
}

struct StateOptionView: View {
    let state: InitialState
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.displayName)
                        .font(Theme.bodyFont(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.ink)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.accent)
                        .font(.system(size: 24))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .fill(isSelected ? Theme.accent.opacity(0.25) : Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .stroke(
                                isSelected ? Theme.borderActive : Theme.border,
                                lineWidth: 1.5
                            )
                    )
            )
            .contentShape(Rectangle())
        }
    }
}

/// 6-digit passcode setup mirroring the parental-gate keypad in
/// `PasscodeEntryView` (numeric-only PIN pad, enter → confirm, masked dots),
/// re-skinned to the parchment theme. Writes the confirmed PIN back into the
/// `passcode`/`confirm` bindings so the onboarding flow can proceed.
struct PasscodeSetupStepView: View {
    @Binding var passcode: String
    @Binding var confirm: String
    @Binding var errorMessage: String
    @Binding var useExisting: Bool
    /// First-account creation hides the "use my current passcode" shortcut.
    var allowUseExisting: Bool = false

    private enum Phase { case enter, confirm }
    @State private var entered: String = ""
    @State private var firstEntry: String = ""
    @State private var phase: Phase = .enter
    @State private var shakeOffset: CGFloat = 0

    private var prompt: String {
        switch phase {
        case .enter:   return "Choose a 6-digit passcode for parental controls"
        case .confirm: return "Confirm your passcode"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundColor(Theme.accent)

            Text("Set a Passcode")
                .font(Theme.titleFont(size: 28))
                .foregroundColor(Theme.ink)

            if useExisting {
                Text("You'll keep using your current parental passcode.")
                    .font(Theme.bodyFont(size: 16))
                    .foregroundColor(Theme.inkMuted)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.accent)
                    Text("Using your current passcode")
                        .font(Theme.bodyFont(size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.ink)
                    Spacer()
                }
                .padding()
                .parchmentCard()
                .padding(.top, 8)
            } else {
                Text(prompt)
                    .font(Theme.bodyFont(size: 16))
                    .foregroundColor(Theme.inkMuted)
                    .multilineTextAlignment(.center)

                // Error
                Text(errorMessage)
                    .font(Theme.bodyFont(size: 14))
                    .foregroundColor(Theme.destructive)
                    .frame(height: 18)
                    .opacity(errorMessage.isEmpty ? 0 : 1)

                // Masked dots
                HStack(spacing: 16) {
                    ForEach(0..<6, id: \.self) { i in
                        Circle()
                            .fill(i < entered.count ? Theme.ink : Theme.border)
                            .frame(width: 14, height: 14)
                            .scaleEffect(i < entered.count ? 1.1 : 1.0)
                            .animation(.spring(response: 0.2), value: entered.count)
                    }
                }
                .offset(x: shakeOffset)
                .padding(.vertical, 8)

                // Numeric keypad
                VStack(spacing: 14) {
                    ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                        HStack(spacing: 24) {
                            ForEach(row, id: \.self) { digit in
                                keyButton("\(digit)")
                            }
                        }
                    }
                    HStack(spacing: 24) {
                        Color.clear.frame(width: 68, height: 68)
                        keyButton("0")
                        Button(action: backspace) {
                            Image(systemName: "delete.left.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Theme.inkMuted)
                                .frame(width: 68, height: 68)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }

            // Reuse current passcode — only for additional children, never first account.
            if allowUseExisting {
                Button {
                    withAnimation { useExisting.toggle(); errorMessage = ""; reset() }
                } label: {
                    Text(useExisting ? "Set a new passcode instead" : "Use my current passcode")
                        .font(Theme.bodyFont(size: 15))
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.accent)
                        .underline()
                }
                .padding(.top, 4)
            }
        }
        .onAppear { syncFromBindings() }
    }

    // MARK: - Key button
    private func keyButton(_ label: String) -> some View {
        Button(action: { append(label) }) {
            Text(label)
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(Theme.ink)
                .frame(width: 68, height: 68)
                .background(Circle().fill(Theme.card))
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                .contentShape(Circle())
        }
    }

    // MARK: - Input logic
    private func append(_ digit: String) {
        guard entered.count < 6 else { return }
        entered += digit
        errorMessage = ""
        if entered.count == 6 { handleComplete() }
    }

    private func backspace() {
        guard !entered.isEmpty else { return }
        entered.removeLast()
        errorMessage = ""
    }

    private func handleComplete() {
        if phase == .enter {
            firstEntry = entered
            entered = ""
            phase = .confirm
        } else {
            if entered == firstEntry {
                // Commit — drives the onboarding's canProceed / Create Profile.
                passcode = entered
                confirm = entered
                errorMessage = ""
            } else {
                shake()
                errorMessage = "passcodes don't match — try again"
                passcode = ""; confirm = ""
                firstEntry = ""; entered = ""
                phase = .enter
            }
        }
    }

    /// Keep local keypad state consistent if we navigate back to this step
    /// after already committing a passcode.
    private func syncFromBindings() {
        if passcode.count == 6 && passcode == confirm {
            entered = passcode
            firstEntry = passcode
            phase = .confirm
        }
    }

    private func reset() {
        entered = ""; firstEntry = ""; phase = .enter
        passcode = ""; confirm = ""
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

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Theme.card)
            .cornerRadius(Theme.radiusMD)
            .foregroundColor(Theme.ink)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(Theme.border, lineWidth: 1.5)
            )
    }
}

#Preview {
    ChildOnboardingView { _ in }
        .environmentObject(AuthManager())
}
