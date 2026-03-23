import SwiftUI

/// Ported from StoryRoadmap.tsx — displays a visual tale-map of unlockable story chapters
/// based on the child's completed stories, and lets the parent launch the next chapter.
struct StoryRoadmapView: View {
    let child: ChildProfile
    let onBack: () -> Void
    let onStartStory: (StoryConfig) -> Void

    @EnvironmentObject var authManager: AuthManager

    @State private var roadmapNodes: [RoadmapNode] = []
    @State private var stats: ChildStatistics?
    @State private var loading = true

    // MARK: - Parchment palette
    private let bg        = Color(red: 0.894, green: 0.835, blue: 0.718)
    private let cardBg    = Color(red: 0.980, green: 0.961, blue: 0.922)
    private let borderClr = Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.28)
    private let ink       = Color(red: 0.078, green: 0.059, blue: 0.039)
    private let unlockedNodeGrad = LinearGradient(
        colors: [Color(red: 0.902, green: 0.784, blue: 0.627), Color(red: 0.784, green: 0.667, blue: 0.549)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private let completedNodeGrad = LinearGradient(
        colors: [Color(red: 0.275, green: 0.510, blue: 0.314), Color(red: 0.196, green: 0.431, blue: 0.235)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private let lockedNodeGrad = LinearGradient(
        colors: [Color(red: 0.706, green: 0.627, blue: 0.549).opacity(0.6),
                 Color(red: 0.627, green: 0.549, blue: 0.471).opacity(0.6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            if loading {
                loadingView
            } else {
                roadmapScrollView
            }
        }
        .navigationBarHidden(true)
        .task { await loadData() }
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(ink).scaleEffect(1.4)
            Text("charting your journey…")
                .font(.custom("PatrickHand-Regular", size: 20))
                .foregroundColor(ink.opacity(0.7))
        }
    }

    // MARK: - Main scroll view
    private var roadmapScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                if let stats = stats {
                    statsBar(stats: stats)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                roadmapPath
                bottomMessage
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(ink)
                }
                Spacer()
            }
            Text("\(child.name)'s tale map")
                .font(.custom("IndieFlower-Regular", size: 30))
                .foregroundColor(ink)
            Text("choose tonight's path")
                .font(.custom("PatrickHand-Regular", size: 16))
                .foregroundColor(ink.opacity(0.65))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(bg.opacity(0.9))
    }

    // MARK: - Stats Bar
    @ViewBuilder
    private func statsBar(stats: ChildStatistics) -> some View {
        HStack(spacing: 0) {
            statCell(value: "\(stats.summary.totalSessions)", label: "tales told")
            Divider()
                .frame(width: 2, height: 44)
                .background(
                    LinearGradient(
                        colors: [.clear, borderClr, .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            statCell(value: "\(Int((Double(stats.summary.avgDuration) / 60.0).rounded()))m", label: "to slumber")
            Divider()
                .frame(width: 2, height: 44)
                .background(
                    LinearGradient(
                        colors: [.clear, borderClr, .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            let drift = stats.summary.avgDriftImprovement ?? 0
            statCell(
                value: "+\(String(format: "%.0f", drift))",
                label: "drift gain",
                valueColor: Color(red: 0.235, green: 0.392, blue: 0.235)
            )
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardBg.opacity(0.82))
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderClr, lineWidth: 2)
        )
    }

    @ViewBuilder
    private func statCell(value: String, label: String, valueColor: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("IndieFlower-Regular", size: 32))
                .fontWeight(.bold)
                .foregroundColor(valueColor ?? ink)
            Text(label)
                .font(.custom("PatrickHand-Regular", size: 14))
                .fontWeight(.bold)
                .foregroundColor(ink.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Roadmap Path
    private var roadmapPath: some View {
        ZStack(alignment: .top) {
            // Dashed vertical guide line
            VStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 3)
                    .overlay(
                        GeometryReader { geo in
                            Path { path in
                                let x = geo.size.width / 2
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: geo.size.height))
                            }
                            .stroke(
                                borderClr.opacity(0.5),
                                style: StrokeStyle(lineWidth: 3, dash: [8, 4])
                            )
                        }
                    )
            }

            // Nodes
            VStack(spacing: 36) {
                ForEach(Array(roadmapNodes.enumerated()), id: \.element.id) { index, node in
                    roadmapNodeRow(node: node, index: index)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: index % 2 == 0 ? .leading : .trailing)
                                    .combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.07), value: roadmapNodes.count)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func roadmapNodeRow(node: RoadmapNode, index: Int) -> some View {
        let leftAligned = index % 2 == 0
        HStack(alignment: .center, spacing: 16) {
            if leftAligned {
                nodeCircle(node)
                nodeInfoCard(node)
                Spacer()
            } else {
                Spacer()
                nodeInfoCard(node)
                nodeCircle(node)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func nodeCircle(_ node: RoadmapNode) -> some View {
        ZStack {
            // Background gradient circle
            Circle()
                .fill(node.unlocked
                      ? (node.completed ? AnyShapeStyle(completedNodeGrad) : AnyShapeStyle(unlockedNodeGrad))
                      : AnyShapeStyle(lockedNodeGrad)
                )
                .frame(width: 88, height: 88)
                .overlay(
                    Circle()
                        .stroke(
                            node.unlocked
                            ? (node.completed
                               ? Color(red: 0.314, green: 0.549, blue: 0.353)
                               : Color(red: 0.235, green: 0.176, blue: 0.118).opacity(0.5))
                            : Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.3),
                            lineWidth: 4
                        )
                )
                .shadow(
                    color: node.unlocked ? .black.opacity(0.2) : .black.opacity(0.08),
                    radius: node.unlocked ? 8 : 4, x: 0, y: node.unlocked ? 6 : 2
                )
                .opacity(node.unlocked ? 1.0 : 0.6)

            // Pulsing glow for newly unlocked nodes
            if node.unlocked && !node.completed && node.progress == 0 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.yellow.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 44
                        )
                    )
                    .frame(width: 88, height: 88)
                    .blur(radius: 8)
                    .scaleEffect(pulseEffect ? 1.35 : 1.0)
                    .opacity(pulseEffect ? 0.6 : 0.25)
                    .animation(
                        .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                        value: pulseEffect
                    )
            }

            // Progress ring
            if node.unlocked && !node.completed && node.progress > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(node.progress) / CGFloat(node.totalStories))
                    .stroke(
                        Color(red: 0.275, green: 0.510, blue: 0.314).opacity(0.85),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
            }

            // Icon or lock
            if node.unlocked {
                Text(node.icon)
                    .font(.system(size: 34))
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 2)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(red: 0.235, green: 0.196, blue: 0.157).opacity(0.5))
            }

            // Checkmark badge
            if node.completed {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.275, green: 0.706, blue: 0.353),
                                     Color(red: 0.196, green: 0.627, blue: 0.275)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.white)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .offset(x: 30, y: -30)
            }

            // Progress label badge
            if node.unlocked && !node.completed {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1, green: 0.863, blue: 0.392))
                    Text("\(node.progress)/\(node.totalStories)")
                        .font(.custom("PatrickHand-Regular", size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0.196, green: 0.157, blue: 0.118).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.235, green: 0.176, blue: 0.118).opacity(0.6), lineWidth: 2)
                )
                .cornerRadius(12)
                .offset(x: 28, y: 32)
            }
        }
        .frame(width: 88, height: 88)
        .contentShape(Circle())
        .onTapGesture { handleSelectNode(node) }
    }

    @ViewBuilder
    private func nodeInfoCard(_ node: RoadmapNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.title)
                .font(.custom("IndieFlower-Regular", size: 20))
                .fontWeight(.bold)
                .foregroundColor(ink.opacity(node.unlocked ? 0.9 : 0.45))
            Text(node.subtitle)
                .font(.custom("PatrickHand-Regular", size: 13))
                .fontWeight(.bold)
                .foregroundColor(Color(red: 0.314, green: 0.235, blue: 0.157).opacity(node.unlocked ? 0.8 : 0.35))
            Text(node.description)
                .font(.custom("PatrickHand-Regular", size: 14))
                .foregroundColor(ink.opacity(node.unlocked ? 0.65 : 0.3))
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 180)
        .background(cardBg.opacity(node.unlocked ? 0.98 : 0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    node.unlocked ? borderClr.opacity(1.3) : borderClr.opacity(0.5),
                    lineWidth: node.unlocked ? 3 : 2
                )
        )
        .cornerRadius(10)
        .shadow(
            color: node.unlocked ? .black.opacity(0.12) : .black.opacity(0.04),
            radius: node.unlocked ? 8 : 3, x: 0, y: 3
        )
    }

    // MARK: - Bottom Message
    private var bottomMessage: some View {
        Text("✨ complete stories to unlock more adventures! each bedtime tale you finish opens new magical worlds to explore ✨")
            .font(.custom("PatrickHand-Regular", size: 16))
            .fontWeight(.bold)
            .foregroundColor(ink.opacity(0.85))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(20)
            .background(cardBg.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderClr, lineWidth: 3)
            )
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
    }

    // MARK: - Pulse animation flag
    @State private var pulseEffect = false

    // MARK: - Actions
    private func handleSelectNode(_ node: RoadmapNode) {
        guard node.unlocked else { return }
        let config = StoryConfig(
            childId: child.id,
            name: child.name,
            age: child.age,
            storytellingTone: child.preferences?.storytellingTone ?? "calming",
            parentPrompt: node.theme,
            initialState: "normal"
        )
        onStartStory(config)
    }

    // MARK: - Data Loading
    private func loadData() async {
        guard let token = authManager.accessToken else {
            await MainActor.run {
                roadmapNodes = generateRoadmap(age: child.age, completedStories: 0)
                loading = false
            }
            return
        }
        do {
            async let storiesFetch = APIService.shared.getStories(childId: child.id, token: token)
            async let statsFetch: ChildStatistics = APIService.shared.getStatistics(childId: child.id, token: token)

            let (stories, fetchedStats) = try await (storiesFetch, statsFetch)
            let completedCount = stories.filter { $0.completed }.count

            await MainActor.run {
                stats = fetchedStats
                roadmapNodes = generateRoadmap(age: child.age, completedStories: completedCount)
                loading = false
                pulseEffect = true
            }
        } catch {
            print("StoryRoadmapView: failed to load data — \(error)")
            await MainActor.run {
                roadmapNodes = generateRoadmap(age: child.age, completedStories: 0)
                loading = false
            }
        }
    }
}

// MARK: - Roadmap Generation Logic (mirrors generateRoadmap in StoryRoadmap.tsx)
private func generateRoadmap(age: Int, completedStories: Int) -> [RoadmapNode] {
    let base: [RoadmapNode] = [
        RoadmapNode(id: 1, title: "Bedtime Basics",      subtitle: "5 stories about settling down",   description: "Learn the art of peaceful sleep",       icon: "🌙", requiredStories: 0,  totalStories: 5, theme: "gentle bedtime routines and calming scenes"),
        RoadmapNode(id: 2, title: "Friendship Tales",    subtitle: "5 stories about friends",          description: "Adventures with caring companions",      icon: "🤝", requiredStories: 5,  totalStories: 5, theme: "friendship, kindness, and sharing"),
        RoadmapNode(id: 3, title: "Nature Wonders",      subtitle: "5 stories in the forest",          description: "Explore magical woodlands",               icon: "🌲", requiredStories: 10, totalStories: 5, theme: "enchanted forests and woodland creatures"),
        RoadmapNode(id: 4, title: "Ocean Dreams",        subtitle: "5 stories under the sea",          description: "Dive into peaceful waters",               icon: "🌊", requiredStories: 15, totalStories: 5, theme: "underwater kingdoms and sea adventures"),
        RoadmapNode(id: 5, title: "Space Voyage",        subtitle: "5 stories among the stars",        description: "Float through the cosmos",                icon: "⭐", requiredStories: 20, totalStories: 5, theme: "starry journeys and space exploration"),
        RoadmapNode(id: 6, title: "Castle Chronicles",   subtitle: "5 stories of brave knights",       description: "Find warmth and courage",                 icon: "🏰", requiredStories: 25, totalStories: 5, theme: "castles, knights, and royal adventures"),
        RoadmapNode(id: 7, title: "Garden Magic",        subtitle: "5 stories in bloom",               description: "Wander through flowers",                  icon: "🌸", requiredStories: 30, totalStories: 5, theme: "magical gardens and blooming wonders"),
        RoadmapNode(id: 8, title: "Mountain Heights",    subtitle: "5 stories on peaks",               description: "Climb to peaceful summits",               icon: "⛰️", requiredStories: 35, totalStories: 5, theme: "mountain adventures and high places"),
    ]

    return base.map { node in
        var n = node
        n.unlocked   = completedStories >= node.requiredStories
        n.completed  = completedStories >= node.requiredStories + node.totalStories
        n.progress   = max(0, min(node.totalStories, completedStories - node.requiredStories))
        return n
    }
}

// MARK: - RoadmapNode model
struct RoadmapNode: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let requiredStories: Int
    let totalStories: Int
    let theme: String

    var unlocked:  Bool = false
    var completed: Bool = false
    var progress:  Int  = 0
}

#Preview {
    let sampleChild = Child(
        id: "preview",
        userId: "u1",
        name: "Lily",
        age: 5,
        dateOfBirth: nil,
        avatar: nil,
        createdAt: Date(),
        updatedAt: Date(),
        preferences: nil
    )
    StoryRoadmapView(
        child: sampleChild,
        onBack: {},
        onStartStory: { _ in }
    )
    .environmentObject(AuthManager())
}
