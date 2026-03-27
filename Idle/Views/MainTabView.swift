import SwiftUI

// MARK: - Nav destination enum
enum NavDestination: Int, CaseIterable {
    case home, journey, analytics, stories, drawings, themes, characters, settings

    var label: String {
        switch self {
        case .home:       return "home"
        case .journey:    return "journey"
        case .analytics:  return "behavioral insights"
        case .stories:    return "story archive"
        case .drawings:   return "drawings collection"
        case .themes:     return "story themes"
        case .characters: return "characters"
        case .settings:   return "settings"
        }
    }

    var icon: String {
        switch self {
        case .home:       return "house.fill"
        case .journey:    return "map.fill"
        case .analytics:  return "chart.bar.fill"
        case .stories:    return "book.fill"
        case .drawings:   return "photo.on.rectangle.angled"
        case .themes:     return "sparkles"
        case .characters: return "person.2.fill"
        case .settings:   return "gearshape.fill"
        }
    }
}

// MARK: - MainTabView
struct MainTabView: View {
    @Binding var currentView: AppView
    @Binding var selectedChild: Child?
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var vitalsManager: VitalsManager

    @State private var children: [ChildProfile] = []
    @State private var isLoading = true
    @State private var selectedDest: NavDestination = .home
    @State private var menuOpen = false

    // Educational lesson selection
    @State private var selectedLesson: LessonDefinition? = nil
    @State private var completedLessonIds: Set<String> = []

    // Bedtime session sheet
    @State private var showBedtimeSession = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isLoading {
                    LoadingView()
                        .onAppear { Task { await loadChildren() } }
                } else if children.isEmpty {
                    ChildOnboardingView { child in
                        children.append(child)
                        selectedChild = child
                    }
                } else {
                    let child = selectedChild ?? children[0]
                    ZStack(alignment: .topTrailing) {
                        pageContent(for: selectedDest, child: child)
                            .scaleEffect(menuOpen ? 0.96 : 1.0)
                            .brightness(menuOpen ? -0.04 : 0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: menuOpen)
                            .allowsHitTesting(!menuOpen)
                            .onTapGesture { if menuOpen { withAnimation { menuOpen = false } } }
                        hamburgerButton
                    }
                }
            }

            if menuOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { menuOpen = false } }
                    .transition(.opacity)
                sidebarDrawer
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: menuOpen)
        .fullScreenCover(isPresented: $showBedtimeSession) {
            if let child = selectedChild ?? children.first.map({ $0 }) {
                BedtimeStorySessionView(child: child) { _, _ in
                    showBedtimeSession = false
                }
                .environmentObject(authManager)
                .environmentObject(vitalsManager)
            }
        }
        .fullScreenCover(item: $selectedLesson) { lesson in
            if let child = selectedChild ?? children.first.map({ $0 }) {
                EducationalStorySessionView(child: child, lesson: lesson) { summary in
                    selectedLesson = nil
                    if summary.lessonProgress >= 100 {
                        completedLessonIds.insert(lesson.id)
                    }
                }
                .environmentObject(authManager)
                .environmentObject(vitalsManager)
            }
        }
    }

    // MARK: - Hamburger button
    private var hamburgerButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                menuOpen.toggle()
            }
        } label: {
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.ink)
                        .frame(width: 22, height: 2.5)
                }
            }
            .padding(12)
            .background(Theme.card)
            .cornerRadius(Theme.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .stroke(Theme.border, lineWidth: 1.5)
            )
            .shadow(color: Theme.cardShadow, radius: 3, x: 0, y: 2)
        }
        .padding(.top, 56)
        .padding(.trailing, 16)
        .zIndex(10)
    }

    // MARK: - Sidebar drawer
    private var sidebarDrawer: some View {
        ZStack(alignment: .topTrailing) {
            Theme.card
                .frame(width: 280)
                .ignoresSafeArea()
                .overlay(
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1.5),
                    alignment: .leading
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: -8, y: 0)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Image("StoryDriftLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                    Text("dream keeper's log")
                        .font(Theme.bodyFont(size: 13))
                        .foregroundColor(Theme.inkMuted)
                        .italic()
                }
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .padding(.bottom, 28)

                Divider()
                    .background(Theme.border)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                ForEach(NavDestination.allCases, id: \.self) { dest in
                    navRow(dest)
                }

                Spacer()
            }
        }
        .frame(width: 280)
        .zIndex(20)
    }

    // MARK: - Nav row
    @ViewBuilder
    private func navRow(_ dest: NavDestination) -> some View {
        let isActive = selectedDest == dest
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedDest = dest
                menuOpen = false
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: dest.icon)
                    .font(.system(size: 17))
                    .foregroundColor(isActive ? Theme.ink : Theme.inkMuted)
                    .frame(width: 24)
                Text(dest.label)
                    .font(Theme.bodyFont(size: 17))
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundColor(isActive ? Theme.ink : Theme.inkMuted)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                isActive
                    ? Theme.accent.opacity(0.35)
                        .cornerRadius(Theme.radiusSM)
                        .padding(.horizontal, 8)
                    : nil
            )
        }
    }

    // MARK: - Page content router
    @ViewBuilder
    private func pageContent(for dest: NavDestination, child: ChildProfile) -> some View {
        switch dest {
        case .home:
            ChildDashboardView(
                child: .constant(child),
                onStartStory: {
                    selectedChild = child
                    currentView = .setup
                }
            )
        case .journey:
            StoryRoadmapView(
                child: child,
                onBack: { withAnimation { selectedDest = .home } },
                onStartStory: { _ in
                    selectedChild = child
                    currentView = .setup
                }
            )
        case .analytics:
            BehavioralStatsView(child: child)
        case .stories:
            StoryArchiveView(childId: child.id)
        case .drawings:
            DrawingsManagerView(onBack: { withAnimation { selectedDest = .home } })
        case .themes:
            StoryThemesView()
        case .characters:
            CharactersView()
        case .settings:
            SettingsView(children: $children, selectedChild: $selectedChild)
        }
    }

    // MARK: - Load children
    private func loadChildren() async {
        guard let token = authManager.accessToken else { isLoading = false; return }
        do {
            children = try await APIService.shared.getChildren(token: token)
            if !children.isEmpty && selectedChild == nil {
                selectedChild = children[0]
            }
            isLoading = false
        } catch {
            print("Error loading children: \(error)")
            isLoading = false
        }
    }
}

// MARK: - LessonDefinition Identifiable for .fullScreenCover(item:)
extension LessonDefinition: Hashable {
    static func == (lhs: LessonDefinition, rhs: LessonDefinition) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    MainTabView(currentView: .constant(.dashboard), selectedChild: .constant(nil))
        .environmentObject(AuthManager())
        .environmentObject(VitalsManager())
}
