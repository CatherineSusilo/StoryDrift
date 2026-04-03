import SwiftUI

// MARK: - Legacy Lesson Catalogue (kept for backwards compatibility)
let lessonCatalogue: [LessonCategory] = [
    LessonCategory(id: "math", title: "Numbers & Maths", emoji: "🔢", color: Color(red: 0.3, green: 0.7, blue: 0.9),
        lessons: [
            LessonDefinition(id: "count10", name: "Counting to 10", description: "Introduce numbers 1–10 through object grouping and sequential ordering.", emoji: "1️⃣", ageMin: 2, ageMax: 5),
        ]
    ),
]

// MARK: - LessonRoadmapView (Duolingo-style Journey)

struct LessonRoadmapView: View {
    let child: ChildProfile
    let completedLessonIds: Set<String>
    let onStartLesson: (LessonDefinition) -> Void
    var refreshTrigger: UUID = UUID()

    @State private var sections: [CurriculumSection] = []
    @State private var progress: ChildProgressResponse? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    // Parchment palette
    private let bg     = Color(red: 0.929, green: 0.894, blue: 0.827)
    private let ink    = Color(red: 0.078, green: 0.059, blue: 0.039)
    private let cardBg = Color(red: 0.980, green: 0.961, blue: 0.922)

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                if isLoading {
                    LoadingView()
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48)).foregroundColor(.orange)
                        Text("Couldn't load journey")
                            .font(.custom("IndieFlower-Regular", size: 22)).foregroundColor(ink)
                        Text(error)
                            .font(.custom("PatrickHand-Regular", size: 15))
                            .foregroundColor(ink.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Button("Try Again") { Task { await loadCurriculum() } }
                            .font(.custom("PatrickHand-Regular", size: 17))
                            .padding(.horizontal, 24).padding(.vertical, 10)
                            .background(Color.orange.opacity(0.8)).cornerRadius(10)
                            .foregroundColor(.white)
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        // ── Sticky header ──────────────────────────────────
                        stickyHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 12)
                            .background(bg)

                        // ── Scrollable roadmap ─────────────────────────────
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                                    sectionBlock(section: section, sectionIndex: idx)
                                }
                                Spacer(minLength: 60)
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .task { await loadCurriculum() }
            .onChange(of: refreshTrigger) { _ in Task { await loadCurriculum() } }
        }
    }

    // MARK: - Sticky header (same style as other pages)

    private var stickyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name greeting — matches other page title style
            Text("Hi, \(child.name.components(separatedBy: " ").first ?? child.name)! 👋")
                .font(Theme.titleFont(size: 32))
                .foregroundColor(Theme.ink)

            if let p = progress {
                let total     = p.sections.reduce(0) { $0 + $1.totalLessons }
                let completed = p.sections.reduce(0) { $0 + $1.completedLessons }

                HStack {
                    Text("\(completed) of \(total) lessons completed")
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(Theme.inkMuted)
                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Theme.border)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(colors: [.cyan, .blue],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(completed) / CGFloat(max(total, 1)),
                                   height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
    }

    // MARK: - Section block (header card + zigzag nodes)

    private func sectionBlock(section: CurriculumSection, sectionIndex: Int) -> some View {
        let sectionColor = Color(hex: section.color) ?? .blue
        let sectionProg  = progress?.sections.first(where: { $0.sectionId == section.id })
        let completed    = sectionProg?.completedLessons ?? 0
        let total        = sectionProg?.totalLessons ?? (section.lessons?.count ?? 0)

        return VStack(spacing: 0) {
            // ── Section header card ──────────────────────────────────────
            HStack(spacing: 14) {
                Text(section.emoji).font(.system(size: 36))
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.name)
                        .font(.custom("IndieFlower-Regular", size: 20))
                        .foregroundColor(.white)
                    Text(section.description)
                        .font(.custom("PatrickHand-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                }
                Spacer()
                // Stars badge
                if total > 0 {
                    VStack(spacing: 1) {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundColor(.yellow)
                            Text("\(completed)/\(total)")
                                .font(.custom("PatrickHand-Regular", size: 13)).foregroundColor(.white)
                        }
                        Text("done").font(.custom("PatrickHand-Regular", size: 11)).foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.18)).cornerRadius(8)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .background(sectionColor)
            .cornerRadius(16)
            .padding(.horizontal, 16)
            .shadow(color: sectionColor.opacity(0.35), radius: 6, x: 0, y: 3)

            // ── Zigzag lesson nodes ──────────────────────────────────────
            if let lessons = section.lessons, !lessons.isEmpty {
                GeometryReader { geo in
                    let w = geo.size.width
                    let xSlots: [CGFloat] = [0.18, 0.50, 0.82, 0.50]
                    let nodeH: CGFloat  = 120   // vertical spacing between nodes
                    let topOffset: CGFloat = 70 // gap between header and first node

                    ZStack {
                        // Dashed connector lines
                        ForEach(0..<lessons.count - 1, id: \.self) { i in
                            let fromX = w * xSlots[i % 4]
                            let fromY = CGFloat(i) * nodeH + topOffset
                            let toX   = w * xSlots[(i + 1) % 4]
                            let toY   = CGFloat(i + 1) * nodeH + topOffset
                            let lessonProg = lessonProgress(id: lessons[i].id)
                            Path { p in
                                p.move(to: CGPoint(x: fromX, y: fromY))
                                p.addCurve(
                                    to: CGPoint(x: toX, y: toY),
                                    control1: CGPoint(x: fromX, y: fromY + (toY - fromY) * 0.45),
                                    control2: CGPoint(x: toX,   y: toY   - (toY - fromY) * 0.45)
                                )
                            }
                            .stroke(
                                lessonProg?.completed == true ? sectionColor.opacity(0.6) : sectionColor.opacity(0.22),
                                style: StrokeStyle(lineWidth: 3, dash: lessonProg?.completed == true ? [] : [7, 5])
                            )
                        }

                        // Lesson nodes
                        ForEach(Array(lessons.enumerated()), id: \.element.id) { i, lesson in
                            let x = w * xSlots[i % 4]
                            let y = CGFloat(i) * nodeH + topOffset
                            lessonNode(lesson: lesson, sectionColor: sectionColor, section: section)
                                .position(x: x, y: y)
                        }
                    }
                    .frame(height: CGFloat(lessons.count) * nodeH + topOffset + 40)
                }
                .frame(height: CGFloat((section.lessons?.count ?? 0)) * 120 + 110)
                .padding(.top, 16)
            } else {
                // Still loading lessons for this section
                HStack {
                    Spacer()
                    ProgressView().tint(sectionColor).padding(.vertical, 24)
                    Spacer()
                }
            }
        }
        .padding(.bottom, 48)  // spacious gap between sections
    }

    // MARK: - Single lesson node

    private func lessonNode(lesson: CurriculumLesson, sectionColor: Color, section: CurriculumSection) -> some View {
        let prog      = lessonProgress(id: lesson.id)
        let completed = prog?.completed ?? false
        let unlocked  = prog?.unlocked  ?? (lesson.unlockAfter == nil)
        let stars     = prog?.stars ?? 0

        return Button {
            guard unlocked else { return }
            let legacyLesson = LessonDefinition(
                id: lesson.id, name: lesson.name, description: lesson.description,
                emoji: section.emoji, ageMin: 2, ageMax: 5,
                curriculumLessonId: lesson.id   // carry the ID directly — no UserDefaults race
            )
            onStartLesson(legacyLesson)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(completed ? sectionColor : unlocked ? cardBg : Color(white: 0.88))
                        .frame(width: 64, height: 64)
                        .shadow(color: unlocked ? sectionColor.opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
                    Circle()
                        .stroke(completed ? sectionColor : unlocked ? sectionColor.opacity(0.6) : Color(white: 0.75), lineWidth: 3)
                        .frame(width: 64, height: 64)

                    if completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    } else if unlocked {
                        Text(section.emoji).font(.system(size: 28))
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(white: 0.55))
                    }
                }

                // Stars row (only if completed)
                if completed && stars > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<3) { i in
                            Image(systemName: i < stars ? "star.fill" : "star")
                                .font(.system(size: 9))
                                .foregroundColor(.yellow)
                        }
                    }
                } else {
                    Color.clear.frame(height: 13)
                }

                Text(lesson.name)
                    .font(.custom("PatrickHand-Regular", size: 11))
                    .foregroundColor(unlocked ? ink : ink.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 80)
            }
        }
        .disabled(!unlocked)
    }

    // MARK: - Helpers

    private func lessonProgress(id: String) -> LessonProgressDetail? {
        progress?.sections.flatMap(\.lessons).first(where: { $0.lessonId == id })
    }

    // MARK: - Data loading

    private func loadCurriculum() async {
        isLoading = true
        errorMessage = nil

        guard let token = UserDefaults.standard.string(forKey: "accessToken") else {
            errorMessage = "Not logged in"; isLoading = false; return
        }

        do {
            async let sectionsTask  = APIService.shared.getCurriculumForAge(age: child.age, token: token)
            async let progressTask  = APIService.shared.getChildCurriculumProgress(childId: child.id, token: token)
            var loadedSections = try await sectionsTask
            progress           = try await progressTask

            // Load all section lessons in parallel
            try await withThrowingTaskGroup(of: (Int, CurriculumSection).self) { group in
                for (i, section) in loadedSections.enumerated() {
                    group.addTask {
                        let full = try await APIService.shared.getCurriculumSection(sectionId: section.id, token: token)
                        return (i, full)
                    }
                }
                for try await (i, full) in group {
                    loadedSections[i] = full
                }
            }

            sections  = loadedSections
            isLoading = false
            print("📚 Loaded \(sections.count) sections with lessons")
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            print("❌ Failed to load curriculum: \(error)")
        }
    }
}

// MARK: - Color hex extension

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a,r,g,b) = (255,(int>>8)*17,(int>>4 & 0xF)*17,(int & 0xF)*17)
        case 6:  (a,r,g,b) = (255,int>>16,int>>8 & 0xFF,int & 0xFF)
        case 8:  (a,r,g,b) = (int>>24,int>>16 & 0xFF,int>>8 & 0xFF,int & 0xFF)
        default: return nil
        }
        self.init(.sRGB,
            red:   Double(r)/255,
            green: Double(g)/255,
            blue:  Double(b)/255,
            opacity: Double(a)/255)
    }
}

// MARK: - Preview

#Preview {
    LessonRoadmapView(
        child: ChildProfile(id: "c1", userId: "u1", name: "Lily", age: 5,
                            createdAt: Date(), updatedAt: Date()),
        completedLessonIds: [],
        onStartLesson: { _ in }
    )
    .environmentObject(AuthManager())
}
