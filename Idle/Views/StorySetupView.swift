import SwiftUI

struct StorySetupView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var child: ChildProfile
    let onStartStory: (StoryConfig) -> Void
    let onBack: () -> Void
    
    @State private var selectedTheme = "Adventure"
    @State private var parentPrompt = ""
    @State private var storytellingTone: StorytellingTone = .calming
    @State private var initialState: InitialState = .normal
    @State private var storyLength: StoryLength = .medium
    @State private var isGenerating = false
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    
    enum StoryLength: String, CaseIterable {
        case short = "Short"
        case medium = "Medium"
        case long = "Long"
        
        var duration: Int {
            switch self {
            case .short: return 10 // 10 minutes
            case .medium: return 15
            case .long: return 20
            }
        }
    }
    
    let storyPrompts = [
        ("🏰", "a princess and her magical castle"),
        ("🌲", "an adventure through enchanted woods"),
        ("🚀", "a journey to the stars and beyond"),
        ("🐉", "a friendly dragon who loves bedtime"),
        ("🌊", "underwater kingdom of mermaids"),
        ("🦄", "unicorns in a rainbow meadow")
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    Button(action: onBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Story Setup")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Placeholder for spacing
                    Color.clear.frame(width: 60)
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Story Prompts
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose a Theme")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(storyPrompts, id: \.1) { emoji, text in
                            StoryPromptCard(
                                emoji: emoji,
                                text: text,
                                isSelected: parentPrompt.contains(text)
                            ) {
                                parentPrompt = text
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Custom Prompt
                VStack(alignment: .leading, spacing: 12) {
                    Text("Or Add Your Own Ideas")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    TextEditor(text: $parentPrompt)
                        .frame(height: 100)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                    
                    Text("Tell us what your child loves! Characters, themes, or anything special.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal)
                
                // Story Length
                VStack(alignment: .leading, spacing: 12) {
                    Text("Story Length")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Picker("Story Length", selection: $storyLength) {
                        ForEach(StoryLength.allCases, id: \.self) { length in
                            Text("\(length.rawValue) (\(length.duration) min)")
                                .tag(length)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                // Storytelling Tone
                VStack(alignment: .leading, spacing: 12) {
                    Text("Storytelling Tone")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 8) {
                        ForEach(StorytellingTone.allCases, id: \.self) { tone in
                            ToneButton(
                                tone: tone,
                                isSelected: storytellingTone == tone
                            ) {
                                storytellingTone = tone
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Initial Energy State
                VStack(alignment: .leading, spacing: 12) {
                    Text("Child's Current State")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 8) {
                        ForEach(InitialState.allCases, id: \.self) { state in
                            StateButton(
                                state: state,
                                isSelected: initialState == state
                            ) {
                                initialState = state
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Start Story Button
                Button(action: handleStartStory) {
                    HStack(spacing: 12) {
                        if isGenerating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 24))
                        }
                        
                        Text(isGenerating ? "Generating Story..." : "Start Bedtime Story")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                .disabled(isGenerating || parentPrompt.isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.15, green: 0.05, blue: 0.25)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
    
    private func handleStartStory() {
        isGenerating = true
        
        let config = StoryConfig(
            childId: child.id,
            themes: [selectedTheme],
            initialState: initialState,
            parentPrompt: parentPrompt
        )
        
        // Simulate story generation delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isGenerating = false
            onStartStory(config)
        }
    }
}

struct StoryPromptCard: View {
    let emoji: String
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 40))
                
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.purple.opacity(0.3) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color.purple : Color.white.opacity(0.1),
                                lineWidth: 2
                            )
                    )
            )
        }
    }
}

struct ToneButton: View {
    let tone: StorytellingTone
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(tone.emoji)
                    .font(.system(size: 24))
                
                Text(tone.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
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
            )
        }
    }
}

struct StateButton: View {
    let state: InitialState
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(state.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
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
            )
        }
    }
}

#Preview {
    StorySetupView(
        child: .constant(ChildProfile(
            id: "1",
            userId: "user1",
            name: "Emma",
            age: 5,
            storytellingTone: .calming,
            parentPrompt: "",
            customCharacters: [],
            uploadedImages: [],
            createdAt: Date(),
            updatedAt: Date()
        )),
        onStartStory: { _ in },
        onBack: {}
    )
    .environmentObject(AuthManager())
}
