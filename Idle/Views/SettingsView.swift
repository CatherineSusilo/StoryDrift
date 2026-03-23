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
        ScrollView {
            VStack(spacing: 24) {
                // Profile Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Children")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    ForEach(children) { child in
                        ChildSelectionCard(
                            child: child,
                            isSelected: selectedChild?.id == child.id,
                            onSelect: {
                                selectedChild = child
                            }
                        )
                    }
                    
                    Button(action: {
                        showingAddChild = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Another Child")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.purple)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                
                // Monitoring Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Vitals Monitoring")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    SettingsRow(
                        icon: "heart.fill",
                        title: "Auto-monitor",
                        subtitle: "Start monitoring during stories",
                        toggle: .constant(true)
                    )
                    
                    SettingsRow(
                        icon: "moon.zzz.fill",
                        title: "Auto-end stories",
                        subtitle: "Stop when child is asleep (90% drift)",
                        toggle: .constant(true)
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                
                // Audio Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Audio")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Narration Voice")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Menu {
                            ForEach(AudioService.availableVoices) { voice in
                                Button(voice.name) {
                                    // Update voice preference
                                }
                            }
                        } label: {
                            HStack {
                                Text("Sarah")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                
                // Advanced Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Advanced")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    SettingsRow(
                        icon: "ladybug.fill",
                        title: "Debug Mode",
                        subtitle: "Show technical information",
                        toggle: $debugMode
                    )
                    
                    if debugMode {
                        VStack(alignment: .leading, spacing: 8) {
                            DebugInfoRow(label: "Heart Rate", value: "\(Int(vitalsManager.currentHeartRate)) bpm")
                            DebugInfoRow(label: "Breathing Rate", value: String(format: "%.1f rpm", vitalsManager.currentBreathingRate))
                            DebugInfoRow(label: "Signal Quality", value: "\(vitalsManager.signalQuality)%")
                            DebugInfoRow(label: "Drift Score", value: "\(Int(vitalsManager.driftScore))%")
                        }
                        .padding()
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                
                // AI & Drawings Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("AI & Drawings")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Button(action: { showAISettings = true }) {
                        HStack {
                            Image(systemName: "paintpalette.fill")
                                .foregroundColor(.purple)
                                .frame(width: 32)
                            Text("AI Customization")
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    }
                    
                    Button(action: { showDrawingsManager = true }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .foregroundColor(.purple)
                                .frame(width: 32)
                            Text("Drawings Collection")
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )

                // About Section
                VStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("StoryDrift")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Version 1.0.0")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding()
                
                // Logout Button
                Button(action: {
                    authManager.logout()
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
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
}

struct ChildSelectionCard: View {
    let child: ChildProfile
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(child.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Age \(child.age)")
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
                            .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                    )
            )
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var toggle: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.purple)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Toggle("", isOn: $toggle)
                .tint(.purple)
        }
    }
}

struct DebugInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.cyan)
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
