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

    /// Destinations that live inside the "collections" dropdown group
    static let collectionItems: [NavDestination] = [.drawings, .themes, .characters]
    /// Top-level destinations shown directly (not inside a group)
    static let topLevel: [NavDestination] = [.home, .journey, .analytics, .stories, .settings]
}

// MARK: - MainTabView
struct MainTabView: View {
    @Binding var currentView: AppView
    @Binding var selectedChild: Child?
    var dashboardRefreshID: UUID = UUID()
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var vitalsManager: VitalsManager
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var children: [ChildProfile] = []
    @State private var isLoading = true
    @State private var selectedDest: NavDestination = .home
    @State private var menuOpen = false
    @State private var collectionsExpanded = false

    // Parental gate
    @StateObject private var gateManager = ParentalGateManager.shared
    @State private var showPasscodeGate = false   // passcode prompt before settings
    @State private var pendingSettingsDest: NavDestination? = nil

    /// Destinations available to child (non-parent) mode
    private let childModeDestinations: Set<NavDestination> = [.home, .stories, .journey, .settings]

    // Educational lesson selection
    @State private var selectedLesson: LessonDefinition? = nil
    @State private var completedLessonIds: Set<String> = []
    @State private var pendingMinigameFrequency: MinigameFrequency = .every5th
    @State private var journeyRefreshID: UUID = UUID()

    // Bedtime session sheet
    @State private var showBedtimeSession = false

    /// True when running on iPhone (compact horizontal size class)
    private var isCompact: Bool { hSizeClass == .compact }

    /// Navigate to a destination, showing the passcode gate for Settings in child mode.
    private func navigate(to dest: NavDestination) {
        if dest == .settings && !gateManager.isParentMode {
            pendingSettingsDest = dest
            showPasscodeGate = true
        } else {
            withAnimation(.spring(response: 0.3)) {
                selectedDest = dest
                menuOpen = false
            }
        }
    }

    var body: some View {
        ZStack {
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
                            // Only scale/dim on iPad sidebar — iPhone uses bottom sheet, no distortion
                            .scaleEffect((!isCompact && menuOpen) ? 0.96 : 1.0)
                            .brightness((!isCompact && menuOpen) ? -0.04 : 0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: menuOpen)
                            .allowsHitTesting(!menuOpen)
                            .onTapGesture { if menuOpen { withAnimation { menuOpen = false } } }
                        hamburgerButton
                    }
                }
            }

            // ── Overlay: dim + menu content ──────────────────────────────────
            if menuOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.3)) { menuOpen = false } }
                    .transition(.opacity)
                    .zIndex(10)

                if isCompact {
                    // iPhone: bottom sheet with scrollable grid of nav options
                    bottomSheetMenu
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                } else {
                    // iPad: side drawer from trailing edge
                    HStack {
                        Spacer()
                        sidebarDrawer
                    }
                    .transition(.move(edge: .trailing))
                    .zIndex(20)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: menuOpen)
        .onAppear {
            if NavDestination.collectionItems.contains(selectedDest) {
                collectionsExpanded = true
            }
        }
        .fullScreenCover(isPresented: $showPasscodeGate) {
            PasscodeEntryView(
                mode: .unlock,
                title: "parent access",
                subtitle: "enter your passcode to open settings"
            ) { _ in
                gateManager.enterParentMode()
                showPasscodeGate = false
                if let dest = pendingSettingsDest {
                    withAnimation(.spring(response: 0.3)) { selectedDest = dest; menuOpen = false }
                    pendingSettingsDest = nil
                }
            } onCancel: {
                showPasscodeGate = false
                pendingSettingsDest = nil
                withAnimation(.spring(response: 0.3)) { selectedDest = .home }
            }
            .environmentObject(authManager)
        }
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
                EducationalStorySessionView(
                    child: child,
                    lesson: lesson,
                    minigameFrequency: pendingMinigameFrequency
                ) { summary in
                    selectedLesson = nil
                    let score = summary.lessonProgress
                    if score >= 80 {
                        completedLessonIds.insert(lesson.id)
                    }
                    // Post completion to backend so progress bar + unlock updates
                    Task {
                        guard let token = authManager.accessToken else {
                            print("❌ completeCurriculumLesson: no token")
                            journeyRefreshID = UUID()
                            return
                        }
                        do {
                            try await APIService.shared.completeCurriculumLesson(
                                childId: child.id,
                                lessonId: lesson.curriculumLessonId ?? lesson.id,
                                score: score,
                                token: token
                            )
                            print("✅ Lesson \(lesson.id) marked complete (score: \(score))")
                        } catch {
                            print("❌ completeCurriculumLesson failed: \(error)")
                        }
                        // Small delay so the fullScreenCover fully dismisses and
                        // LessonRoadmapView is back in the hierarchy before we trigger reload
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        journeyRefreshID = UUID()
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

    // MARK: - Bottom sheet menu (iPhone / compact)
    private var bottomSheetMenu: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Theme.border)
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                // Logo + title
                HStack(spacing: 10) {
                    Image("StoryDriftLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                    Text("dream keeper's log")
                        .font(Theme.bodyFont(size: 13))
                        .foregroundColor(Theme.inkMuted)
                        .italic()
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                Divider()
                    .background(Theme.border)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // 2-column grid of top-level nav destinations
                let collectionsActive = NavDestination.collectionItems.contains(selectedDest)
                let visibleTopLevel = gateManager.isParentMode
                    ? NavDestination.topLevel
                    : NavDestination.topLevel.filter { childModeDestinations.contains($0) }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                    ForEach(visibleTopLevel, id: \.self) { dest in
                        compactNavTile(dest)
                    }
                    if gateManager.isParentMode {
                        Button {
                            withAnimation(.spring(response: 0.3)) { collectionsExpanded.toggle() }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(collectionsActive ? Theme.ink : Theme.inkMuted)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(collectionsActive ? Theme.accent.opacity(0.4) : Color.clear))
                                    Image(systemName: collectionsExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Theme.inkMuted)
                                        .offset(x: 4, y: -4)
                                }
                                Text("collections")
                                    .font(Theme.bodyFont(size: 11))
                                    .foregroundColor(collectionsActive ? Theme.ink : Theme.inkMuted)
                                    .fontWeight(collectionsActive ? .bold : .regular)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .fill(collectionsActive ? Theme.accent.opacity(0.2) : Color.clear))
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal, 8)

                if gateManager.isParentMode && collectionsExpanded {
                    VStack(spacing: 0) {
                        ForEach(NavDestination.collectionItems, id: \.self) { dest in
                            compactCollectionRow(dest)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer().frame(height: 8)

                Divider()
                    .background(Theme.border)
                    .padding(.horizontal, 16)

                Button(action: { authManager.logout() }) {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16))
                        Text("sign out")
                            .font(Theme.bodyFont(size: 16))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(Theme.destructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }

                Spacer().frame(height: 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: -6)
            )
            .padding(.horizontal, 0)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Compact nav tile (for bottom sheet)
    private func compactNavTile(_ dest: NavDestination) -> some View {
        let isActive = selectedDest == dest
        return Button {
            navigate(to: dest)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: dest.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isActive ? Theme.ink : Theme.inkMuted)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(isActive ? Theme.accent.opacity(0.4) : Color.clear)
                    )
                Text(dest.label)
                    .font(Theme.bodyFont(size: 11))
                    .foregroundColor(isActive ? Theme.ink : Theme.inkMuted)
                    .fontWeight(isActive ? .bold : .regular)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .fill(isActive ? Theme.accent.opacity(0.2) : Color.clear)
            )
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Compact collection row (expanded sub-item in bottom sheet)
    private func compactCollectionRow(_ dest: NavDestination) -> some View {
        let isActive = selectedDest == dest
        return Button {
            navigate(to: dest)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: dest.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isActive ? Theme.ink : Theme.inkMuted)
                    .frame(width: 28)
                Text(dest.label)
                    .font(Theme.bodyFont(size: 15))
                    .foregroundColor(isActive ? Theme.ink : Theme.inkMuted)
                    .fontWeight(isActive ? .bold : .regular)
                Spacer()
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .fill(isActive ? Theme.accent.opacity(0.2) : Theme.background.opacity(0.5))
            )
            .padding(.vertical, 2)
        }
    }

    // MARK: - Sidebar drawer (iPad / regular)
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

                ScrollView {
                    VStack(spacing: 0) {
                        let visibleTop = gateManager.isParentMode
                            ? NavDestination.topLevel
                            : NavDestination.topLevel.filter { childModeDestinations.contains($0) }
                        ForEach(visibleTop, id: \.self) { dest in
                            navRow(dest)
                        }

                        // Collections expandable group — parent mode only
                        if gateManager.isParentMode {
                        let collectionsActive = NavDestination.collectionItems.contains(selectedDest)
                        Button {
                            withAnimation(.spring(response: 0.3)) { collectionsExpanded.toggle() }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 17))
                                    .foregroundColor(collectionsActive ? Theme.ink : Theme.inkMuted)
                                    .frame(width: 24)
                                Text("collections")
                                    .font(Theme.bodyFont(size: 17))
                                    .fontWeight(collectionsActive ? .bold : .regular)
                                    .foregroundColor(collectionsActive ? Theme.ink : Theme.inkMuted)
                                Spacer()
                                Image(systemName: collectionsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.inkMuted)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .background(
                                collectionsActive
                                    ? Theme.accent.opacity(0.35)
                                        .cornerRadius(Theme.radiusSM)
                                        .padding(.horizontal, 8)
                                    : nil
                            )
                        }

                        if collectionsExpanded {
                            VStack(spacing: 0) {
                                ForEach(NavDestination.collectionItems, id: \.self) { dest in
                                    navRow(dest, indented: true)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        } // end if gateManager.isParentMode
                    }
                }

                Spacer()

                Divider()
                    .background(Theme.border)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                Button(action: { authManager.logout() }) {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 17))
                            .foregroundColor(Theme.destructive)
                            .frame(width: 24)
                        Text("sign out")
                            .font(Theme.bodyFont(size: 17))
                            .foregroundColor(Theme.destructive)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: 280)
        .zIndex(20)
    }

    // MARK: - Nav row (iPad sidebar)
    @ViewBuilder
    private func navRow(_ dest: NavDestination, indented: Bool = false) -> some View {
        let isActive = selectedDest == dest
        Button {
            navigate(to: dest)
        } label: {
            HStack(spacing: 14) {
                if indented {
                    Rectangle().fill(Color.clear).frame(width: 16)
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 2, height: 20)
                        .cornerRadius(1)
                }
                Image(systemName: dest.icon)
                    .font(.system(size: indented ? 15 : 17))
                    .foregroundColor(isActive ? Theme.ink : Theme.inkMuted)
                    .frame(width: 24)
                Text(dest.label)
                    .font(Theme.bodyFont(size: indented ? 15 : 17))
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundColor(isActive ? Theme.ink : Theme.inkMuted)
                Spacer()
            }
            .padding(.vertical, indented ? 10 : 12)
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
                refreshID: dashboardRefreshID,
                onStartStory: {
                    selectedChild = child
                    currentView = .setup
                }
            )
        case .journey:
            LessonRoadmapView(
                child: child,
                completedLessonIds: completedLessonIds,
                onStartLesson: { lesson in
                    selectedChild = child
                    selectedLesson = lesson
                },
                refreshTrigger: journeyRefreshID
            )
        case .analytics:
            BehavioralStatsView(child: child, refreshID: dashboardRefreshID)
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
