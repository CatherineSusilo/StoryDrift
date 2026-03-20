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
    @State private var isCreating = false
    
    let onComplete: (ChildProfile) -> Void
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.15, green: 0.05, blue: 0.25)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index <= currentStep ? Color.purple : Color.white.opacity(0.3))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                ScrollView {
                    VStack(spacing: 32) {
                        switch currentStep {
                        case 0:
                            Step1View(name: $childName, age: $childAge)
                        case 1:
                            Step2View(tone: $selectedTone)
                        case 2:
                            Step3View(prompt: $parentPrompt)
                        case 3:
                            Step4View(state: $selectedState)
                        default:
                            EmptyView()
                        }
                    }
                    .padding()
                }
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(16)
                    }
                    
                    Button(currentStep == 3 ? "Create Profile" : "Next") {
                        if currentStep == 3 {
                            createChild()
                        } else {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .disabled(isCreating || !canProceed)
                }
                .padding()
            }
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case 0:
            return !childName.isEmpty && childAge >= 2 && childAge <= 12
        case 2:
            return !parentPrompt.isEmpty
        default:
            return true
        }
    }
    
    private func createChild() {
        guard let token = authManager.accessToken,
              let userId = authManager.user?.id else {
            return
        }
        
        isCreating = true
        
        let child = ChildProfile(
            id: UUID().uuidString,
            userId: userId,
            name: childName,
            age: childAge,
            storytellingTone: selectedTone,
            parentPrompt: parentPrompt,
            uploadedImages: [],
            customCharacters: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        Task {
            do {
                let createdChild = try await APIService.shared.createChild(
                    profile: child,
                    token: token
                )
                
                DispatchQueue.main.async {
                    onComplete(createdChild)
                    dismiss()
                }
            } catch {
                print("Error creating child: \(error)")
                isCreating = false
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
                .foregroundColor(.purple)
            
            Text("Let's create a profile")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text("Tell us about your child")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Child's Name")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                TextField("Enter name", text: $name)
                    .textFieldStyle(CustomTextFieldStyle())
                
                Text("Age")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.top, 8)
                
                Picker("Age", selection: $age) {
                    ForEach(2...12, id: \.self) { age in
                        Text("\(age) years old").tag(age)
                    }
                }
                .pickerStyle(.wheel)
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
                .foregroundColor(.purple)
            
            Text("Choose a Tone")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text("What storytelling style does your child prefer?")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(tone.rawValue.capitalized)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 24))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.purple.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color.purple : Color.white.opacity(0.1),
                                lineWidth: 2
                            )
                    )
            )
        }
    }
}

struct Step3View: View {
    @Binding var prompt: String
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.purple)
            
            Text("Personalize Stories")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text("Tell us about your child's interests, favorite characters, or anything special")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Parent Prompt")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                TextEditor(text: $prompt)
                    .frame(height: 150)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                
                Text("Example: Loves unicorns, enjoys space adventures, has a teddy bear named Mr. Snuggles")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
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
                .foregroundColor(.purple)
            
            Text("Initial State")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text("How energetic is your child typically at bedtime?")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 24))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.purple.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color.purple : Color.white.opacity(0.1),
                                lineWidth: 2
                            )
                    )
            )
        }
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .foregroundColor(.white)
    }
}

#Preview {
    ChildOnboardingView { _ in }
        .environmentObject(AuthManager())
}
