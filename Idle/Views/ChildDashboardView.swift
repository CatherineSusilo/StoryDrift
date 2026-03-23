import SwiftUI

struct ChildDashboardView: View {
    @Binding var child: ChildProfile
    @EnvironmentObject var vitalsManager: VitalsManager
    @State private var recentStories: [Story] = []
    @State private var statistics: ChildStatistics?
    let onStartStory: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Good evening,")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(child.name)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 20)
                
                // Start Story Button
                Button(action: onStartStory) {
                    HStack {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 24))
                        
                        Text("Start Bedtime Story")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                .padding(.horizontal)
                
                // Quick Stats
                if let stats = statistics {
                    QuickStatsCard(stats: stats)
                        .padding(.horizontal)
                }
                
                // Recent Stories
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Stories")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal)
                    
                    if recentStories.isEmpty {
                        EmptyStateView(
                            icon: "book",
                            message: "No stories yet.\nStart your first bedtime adventure!"
                        )
                        .padding()
                    } else {
                        ForEach(recentStories.prefix(3)) { story in
                            StoryCardView(story: story)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.top)
                
                // Drift Meter Preview (if monitoring)
                if vitalsManager.isMonitoring {
                    DriftMeterPreview()
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
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
        .task {
            await loadDashboardData()
        }
    }
    
    private func loadDashboardData() async {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            return
        }
        
        do {
            async let storiesTask = APIService.shared.getStories(
                childId: child.id,
                token: token
            )
            async let statsTask = APIService.shared.getStatistics(
                childId: child.id,
                token: token
            )
            
            recentStories = try await storiesTask
            statistics = try await statsTask
        } catch {
            print("Error loading dashboard data: \(error)")
        }
    }
}

struct QuickStatsCard: View {
    let stats: ChildStatistics
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                StatItem(
                    value: "\(stats.summary.totalSessions)",
                    label: "Stories",
                    icon: "book.fill",
                    color: .purple
                )
                
                StatItem(
                    value: formatDuration(TimeInterval(stats.summary.avgDuration)),
                    label: "Avg Sleep Time",
                    icon: "moon.zzz.fill",
                    color: .blue
                )
            }
            
            HStack(spacing: 16) {
                StatItem(
                    value: "\(stats.summary.completedSessions)/\(stats.summary.totalSessions)",
                    label: "Completion",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                StatItem(
                    value: formatDuration(TimeInterval(stats.summary.avgDuration)),
                    label: "Avg Duration",
                    icon: "clock.fill",
                    color: .orange
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes)m"
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
    }
}

struct StoryCardView: View {
    let story: Story
    
    var body: some View {
        HStack(spacing: 16) {
            // Story thumbnail
            if let firstImage = story.images.first,
               let url = URL(string: firstImage) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.purple.opacity(0.3)
                }
                .frame(width: 80, height: 80)
                .cornerRadius(12)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(story.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text(story.themes.joined(separator: ", "))
                    .font(.system(size: 14))
                    .foregroundColor(.purple.opacity(0.8))
                
                Text(formatDate(story.startTime))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            if story.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct DriftMeterPreview: View {
    @EnvironmentObject var vitalsManager: VitalsManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Drift Score")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(vitalsManager.getDriftPercentage())%")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.cyan)
            }
            
            ProgressView(value: vitalsManager.driftScore / 100)
                .tint(.cyan)
                .scaleEffect(y: 2)
            
            Text(vitalsManager.getDriftStatus())
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
}

struct EmptyStateView: View {
    let icon: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

#Preview {
    ChildDashboardView(
        child: .constant(Child(
            id: "1", userId: "user1", name: "Emma", age: 5,
            dateOfBirth: nil, avatar: nil,
            createdAt: Date(), updatedAt: Date(), preferences: nil
        )),
        onStartStory: {}
    )
    .environmentObject(VitalsManager())
}
