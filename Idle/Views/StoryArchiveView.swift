import SwiftUI

struct StoryArchiveView: View {
    @EnvironmentObject var apiService: APIService
    @State private var stories: [Story] = []
    @State private var isLoading = true
    @State private var sortBy: SortOption = .date
    
    let childId: String
    
    var sortedStories: [Story] {
        switch sortBy {
        case .date:
            return stories.sorted { $0.generatedAt > $1.generatedAt }
        case .duration:
            return stories.sorted { $0.duration > $1.duration }
        case .drift:
            return stories.sorted { ($0.driftScores.last ?? 0) > ($1.driftScores.last ?? 0) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Story Archive")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(stories.count) stories")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                Menu {
                    Button(action: { sortBy = .date }) {
                        Label("Sort by Date", systemImage: "calendar")
                    }
                    Button(action: { sortBy = .duration }) {
                        Label("Sort by Duration", systemImage: "timer")
                    }
                    Button(action: { sortBy = .drift }) {
                        Label("Sort by Drift", systemImage: "moon.zzz.fill")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortBy.rawValue)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Spacer()
            } else if stories.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(sortedStories) { story in
                            StoryArchiveCard(story: story)
                        }
                    }
                    .padding()
                }
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
        .task {
            await loadStories()
        }
    }
    
    private func loadStories() async {
        do {
            stories = try await apiService.getStories(childId: childId)
            isLoading = false
        } catch {
            print("Failed to load stories: \(error)")
            isLoading = false
        }
    }
}

enum SortOption: String {
    case date = "Date"
    case duration = "Duration"
    case drift = "Drift Score"
}

struct StoryArchiveCard: View {
    let story: Story
    @State private var showingDetails = false
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: story.generatedAt)
    }
    
    private var formattedDuration: String {
        let minutes = Int(story.duration / 60)
        return "\(minutes) min"
    }
    
    private var finalDrift: Int {
        Int(story.driftScores.last ?? 0)
    }
    
    var body: some View {
        Button(action: { showingDetails = true }) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        Text(formattedDate)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    if story.completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 24))
                    }
                }
                
                // Themes
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(story.themes, id: \.self) { theme in
                            Text(theme)
                                .font(.system(size: 12))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                }
                
                // Stats
                HStack(spacing: 24) {
                    StatItem(
                        icon: "timer",
                        value: formattedDuration,
                        color: .blue
                    )
                    
                    StatItem(
                        icon: "book.pages",
                        value: "\(story.paragraphs.count) parts",
                        color: .orange
                    )
                    
                    StatItem(
                        icon: "moon.zzz.fill",
                        value: "\(finalDrift)% drift",
                        color: .cyan
                    )
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .sheet(isPresented: $showingDetails) {
            StoryDetailsView(story: story)
        }
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No Stories Yet")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Start creating magical bedtime stories")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StoryDetailsView: View {
    let story: Story
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(story.paragraphs.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Part \(index + 1)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.purple)
                            
                            Text(story.paragraphs[index].text)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
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
            .navigationTitle(story.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    StoryArchiveView(childId: "child1")
        .environmentObject(APIService())
}
