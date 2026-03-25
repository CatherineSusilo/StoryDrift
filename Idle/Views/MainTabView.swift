import SwiftUI

// MARK: - Nav destination enum

enum NavDestination: Int, CaseIterable {
    case home, bedtime, learn, analytics, stories, settings

    var label: String {
        switch self {
        case .home:      return "home"
        case .bedtime:   return "bedtime"
        case .learn:     return "learn"
        case .analytics: return "behavioral insights"
        case .stories:   return "story archive"
        case .settings:  return "settings"
        }
    }

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .bedtime:   return "moon.zzz.fill"
        case .learn:     return "star.fill"
        case .analytics: return "chart.bar.fill"
        case .stories:   return "book.fill"
        case .settings:  return "gearshape.fill"
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
            // ── Main content ──
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

            // ── Sidebar drawer ──
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
        // Bedtime session — presented full-screen
        .fullScreenCover(isPresented: $showBedtimeSession) {
            if let child = selectedChild ?? children.first.map({ $0 }) {
                BedtimeStorySessionView(child: child) { driftHistory, duration in
                    showBedtimeSession = false
                    // Could post session summary here
                }
                .environmentObject(authManager)
                .environmentObject(vitalsManager)
            }
        }
        // Educational session — presented full-screen
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
                // App header
                VStack(alignment: .leading, spacing: 4) {
                    Text("🌙")
                        .font(.system(size: 36))
                    Text("StoryDrift")
                        .font(Theme.titleFont(size: 26))
                        .foregroundColor(Theme.ink)
                }
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .padding(.bottom, 28)

                Divider()
                    .background(Theme.border)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // ── Bedtime section ──
                sectionLabel("Bedtime")
                navRow(.home)
                navRow(.bedtime)

                // ── Learn section ──
                sectionLabel("Learning")
                navRow(.learn)

                // ── Account section ──
                sectionLabel("Account")
                navRow(.analytics)
                navRow(.stories)
                navRow(.settings)

                Spacer()
            }
        }
        .frame(width: 280)
        .zIndex(20)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.inkMuted)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    // MARK: - Single nav row

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
                    .foregroundColor(isActive ? iconColor(dest) : Theme.inkMuted)
                    .frame(width: 24)
                Text(dest.label)
                    .font(Theme.bodyFont(size: 17))
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundColor(isActive ? Theme.ink : Theme.inkMuted)
                Spacer()

                // Badges
                if dest == .bedtime {
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo)
                        .cornerRadius(4)
                }
                if dest == .learn {
                    Text("\(completedLessonIds.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.cyan))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                isActive
                    ? iconColor(dest).opacity(0.12)
                        .cornerRadius(Theme.radiusSM)
                        .padding(.horizontal, 8)
                    : nil
            )
        }
    }

    private func iconColor(_ dest: NavDestination) -> Color {
        switch dest {
        case .bedtime: return Color.indigo
        case .learn:   return Color.cyan
        default:       return Theme.accent
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

        case .bedtime:
            // Bedtime tab: setup + launch button (no interactive elements in session)
            bedtimeTabView(child: child)

        case .learn:
            // Educational tab: Duolingo-style lesson roadmap
            LessonRoadmapView(
                child: child,
                completedLessonIds: completedLessonIds,
                onStartLesson: { lesson in
                    selectedLesson = lesson
                }
            )

        case .analytics:
            BehavioralStatsView(child: child)

        case .stories:
            StoryArchiveView(childId: child.id)

        case .settings:
            SettingsView(children: $children, selectedChild: $selectedChild)
        }
    }

    // MARK: - Bedtime tab landing page

    private func bedtimeTabView(child: ChildProfile) -> some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Moon illustration
                VStack(spacing: 16) {
                    Text("🌙")
                        .font(.system(size: 80))
                    Text("Bedtime Stories")
                        .font(Theme.titleFont(size: 28))
                        .foregroundColor(Theme.ink)
                    Text("Personalised stories that drift\n\(child.name.components(separatedBy: " ").first ?? child.name) gently to sleep")
                        .font(Theme.bodyFont(size: 16))
                        .foregroundColor(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                }

                // Feature pills
                VStack(spacing: 12) {
                    featurePill(icon: "waveform.path.ecg", text: "Adapts to biometric signals in real time", color: .indigo)
                    featurePill(icon: "photo.fill",        text: "Scene images fade as you drift to sleep", color: .purple)
                    featurePill(icon: "speaker.wave.2",    text: "Voice slows as drift score rises",       color: .blue)
                    featurePill(icon: "moon.stars",        text: "No interactive elements — pure story",   color: .indigo)
                }
                .padding(.horizontal, 32)

                Spacer()

                // Start button
                Button {
                    showBedtimeSession = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 20))
                        Text("Begin Tonight's Story")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [Color(red: 0.35, green: 0.2, blue: 0.75),
                                                Color(red: 0.25, green: 0.1, blue: 0.55)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(18)
                    .shadow(color: Color.indigo.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
    }

    private func featurePill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .cornerRadius(8)
            Text(text)
                .font(Theme.bodyFont(size: 14))
                .foregroundColor(Theme.inkMuted)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(14)
        .background(Theme.card)
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.border, lineWidth: 1)
        )
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
