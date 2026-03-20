import SwiftUI

struct BehavioralStatsView: View {
    let child: ChildProfile
    @State private var statistics: ChildStatistics?
    @State private var isLoading = true
    @State private var selectedMetric: MetricType = .heartRate
    
    enum MetricType: String, CaseIterable {
        case heartRate = "Heart Rate"
        case breathingRate = "Breathing Rate"
        case sleepOnset = "Sleep Onset"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                Text("Analytics")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(40)
                } else if let stats = statistics {
                    // Summary Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        MetricCard(
                            title: "Total Stories",
                            value: "\(stats.totalStories)",
                            icon: "book.fill",
                            color: .purple
                        )
                        
                        MetricCard(
                            title: "Completion Rate",
                            value: "\(Int(stats.completionRate * 100))%",
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                        
                        MetricCard(
                            title: "Avg Sleep Time",
                            value: formatDuration(stats.averageSleepOnset),
                            icon: "moon.zzz.fill",
                            color: .blue
                        )
                        
                        MetricCard(
                            title: "Avg Duration",
                            value: formatDuration(stats.averageDuration),
                            icon: "timer.fill",
                            color: .orange
                        )
                    }
                    .padding(.horizontal)
                    
                    // Vitals Chart
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Vitals Trends")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        // Metric selector
                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(MetricType.allCases, id: \.self) { metric in
                                Text(metric.rawValue).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        if !stats.vitalsHistory.isEmpty {
                            VitalsChartView(
                                data: stats.vitalsHistory,
                                metric: selectedMetric
                            )
                            .frame(height: 200)
                        } else {
                            EmptyStateView(
                                icon: "chart.line.uptrend.xyaxis",
                                message: "Not enough data yet.\nComplete more stories to see trends."
                            )
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.05))
                    )
                    .padding(.horizontal)
                } else {
                    EmptyStateView(
                        icon: "chart.bar",
                        message: "No statistics available yet."
                    )
                    .padding(40)
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
            await loadStatistics()
        }
    }
    
    private func loadStatistics() async {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            isLoading = false
            return
        }
        
        do {
            statistics = try await APIService.shared.getStatistics(
                childId: child.id,
                token: token
            )
            isLoading = false
        } catch {
            print("Error loading statistics: \(error)")
            isLoading = false
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes)m"
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}

struct VitalsChartView: View {
    let data: [VitalsSnapshot]
    let metric: BehavioralStatsView.MetricType
    
    private var chartData: [Double] {
        data.map { snapshot in
            switch metric {
            case .heartRate:
                return snapshot.avgHeartRate
            case .breathingRate:
                return snapshot.avgBreathingRate
            case .sleepOnset:
                return Double(snapshot.date.timeIntervalSinceReferenceDate)
            }
        }
    }
    
    var body: some View {
        // Simple line chart representation
        GeometryReader { geometry in
            Path { path in
                guard !chartData.isEmpty else { return }
                
                let maxValue = chartData.max() ?? 1
                let minValue = chartData.min() ?? 0
                let range = maxValue - minValue
                
                let stepX = geometry.size.width / CGFloat(chartData.count - 1)
                
                for (index, value) in chartData.enumerated() {
                    let x = CGFloat(index) * stepX
                    let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                    let y = geometry.size.height * (1 - normalizedValue)
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.purple, lineWidth: 3)
        }
        .padding()
    }
}

struct StoryArchiveView: View {
    let child: ChildProfile
    @State private var stories: [Story] = []
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Story Archive")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(40)
                } else if stories.isEmpty {
                    EmptyStateView(
                        icon: "book",
                        message: "No stories yet.\nStart creating bedtime adventures!"
                    )
                    .padding(40)
                } else {
                    ForEach(stories) { story in
                        StoryArchiveCard(story: story)
                            .padding(.horizontal)
                    }
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
            await loadStories()
        }
    }
    
    private func loadStories() async {
        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            isLoading = false
            return
        }
        
        do {
            stories = try await APIService.shared.getStories(
                childId: child.id,
                token: token
            )
            isLoading = false
        } catch {
            print("Error loading stories: \(error)")
            isLoading = false
        }
    }
}

struct StoryArchiveCard: View {
    let story: Story
    
    var body: some View {
        VStack(spacing: 16) {
            // Story images gallery
            if !story.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(story.images, id: \.self) { imageURL in
                            if let url = URL(string: imageURL) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.purple.opacity(0.3)
                                }
                                .frame(width: 120, height: 120)
                                .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(story.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                HStack {
                    ForEach(story.themes, id: \.self) { theme in
                        Text(theme)
                            .font(.system(size: 12))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                
                HStack {
                    Text(formatDate(story.generatedAt))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    if story.completed {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Completed")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct SettingsView: View {
    @Binding var children: [ChildProfile]
    @Binding var selectedChild: ChildProfile?
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Settings")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
                
                // Children profiles
                VStack(alignment: .leading, spacing: 16) {
                    Text("Children Profiles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    ForEach(children) { child in
                        ChildProfileRow(
                            child: child,
                            isSelected: selectedChild?.id == child.id
                        ) {
                            selectedChild = child
                        }
                    }
                    
                    Button(action: {
                        // Add new child
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Another Child")
                        }
                        .foregroundColor(.purple)
                        .font(.system(size: 16, weight: .medium))
                    }
                    .padding()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal)
                
                // Account section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Account")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if let user = authManager.user {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name ?? "User")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Text(user.email)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            Spacer()
                        }
                        .padding()
                    }
                    
                    Button(action: {
                        authManager.logout()
                    }) {
                        Text("Sign Out")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal)
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
    }
}

struct ChildProfileRow: View {
    let child: ChildProfile
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(child.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("\(child.age) years old")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.purple)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.purple.opacity(0.2) : Color.clear)
            )
        }
    }
}

#Preview {
    BehavioralStatsView(
        child: ChildProfile(
            id: "1",
            userId: "user1",
            name: "Emma",
            age: 5,
            storytellingTone: .calming,
            parentPrompt: "Loves unicorns",
            uploadedImages: [],
            customCharacters: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    )
}
