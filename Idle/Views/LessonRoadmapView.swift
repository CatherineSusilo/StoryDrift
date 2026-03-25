import SwiftUI

// MARK: - Lesson Catalogue

struct LessonCategory: Identifiable {
    let id: String
    let title: String
    let emoji: String
    let color: Color
    let lessons: [LessonDefinition]
}

struct LessonDefinition: Identifiable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let ageMin: Int
    let ageMax: Int
}

let lessonCatalogue: [LessonCategory] = [
    LessonCategory(id: "math", title: "Numbers & Maths", emoji: "🔢", color: Color(red: 0.3, green: 0.7, blue: 0.9),
        lessons: [
            LessonDefinition(id: "count10",  name: "Counting to 10",  description: "Introduce numbers 1–10 through object grouping and sequential ordering.", emoji: "1️⃣", ageMin: 2, ageMax: 5),
            LessonDefinition(id: "count20",  name: "Counting to 20",  description: "Extend counting to 20 using pairs and grouping.", emoji: "2️⃣", ageMin: 4, ageMax: 6),
            LessonDefinition(id: "shapes",   name: "Shapes Around Us", description: "Identify circles, squares, triangles, stars in the story world.", emoji: "🔷", ageMin: 2, ageMax: 5),
            LessonDefinition(id: "add5",     name: "Adding Up to 5",  description: "Simple addition stories where characters collect and combine objects.", emoji: "➕", ageMin: 4, ageMax: 7),
            LessonDefinition(id: "subtract", name: "Taking Away",     description: "Subtraction stories with objects disappearing or being gifted away.", emoji: "➖", ageMin: 5, ageMax: 8),
        ]
    ),
    LessonCategory(id: "letters", title: "Letters & Words", emoji: "🔤", color: Color(red: 0.95, green: 0.6, blue: 0.2),
        lessons: [
            LessonDefinition(id: "vowels",   name: "Vowel Sounds",    description: "A, E, I, O, U — characters meet objects for each vowel.", emoji: "🅰️", ageMin: 3, ageMax: 6),
            LessonDefinition(id: "abc",      name: "The Alphabet",    description: "Journey through A–Z with a character collecting one thing per letter.", emoji: "📝", ageMin: 3, ageMax: 5),
            LessonDefinition(id: "rhyme",    name: "Rhyming Words",   description: "Characters discover pairs of rhyming objects in the world.", emoji: "🎵", ageMin: 3, ageMax: 6),
            LessonDefinition(id: "sight5",   name: "Sight Words",     description: "Learn the, a, is, it, in through story repetition.", emoji: "👁️", ageMin: 4, ageMax: 7),
        ]
    ),
    LessonCategory(id: "science", title: "Science & Nature", emoji: "🔬", color: Color(red: 0.35, green: 0.8, blue: 0.45),
        lessons: [
            LessonDefinition(id: "animals",  name: "Animal Sounds",   description: "Each story character is an animal — child learns its sound and habitat.", emoji: "🐾", ageMin: 2, ageMax: 5),
            LessonDefinition(id: "seasons",  name: "Four Seasons",    description: "The character travels through spring, summer, autumn, and winter.", emoji: "🍂", ageMin: 3, ageMax: 6),
            LessonDefinition(id: "plants",   name: "How Plants Grow", description: "A seed's journey from soil to flower, step by step.", emoji: "🌱", ageMin: 4, ageMax: 7),
            LessonDefinition(id: "weather",  name: "Weather Patterns", description: "Sun, rain, wind, snow — the character navigates each.", emoji: "⛈️", ageMin: 3, ageMax: 6),
        ]
    ),
    LessonCategory(id: "life", title: "Life Skills", emoji: "❤️", color: Color(red: 0.9, green: 0.35, blue: 0.55),
        lessons: [
            LessonDefinition(id: "emotions", name: "My Feelings",     description: "Characters experience joy, sadness, anger and frustration — and how to handle them.", emoji: "😊", ageMin: 2, ageMax: 6),
            LessonDefinition(id: "sharing",  name: "Sharing & Kindness", description: "Story shows the joy of giving, waiting turns, and helping others.", emoji: "🤝", ageMin: 2, ageMax: 6),
            LessonDefinition(id: "colours",  name: "Colours of the World", description: "Character paints the world in different colours and learns their names.", emoji: "🎨", ageMin: 2, ageMax: 4),
            LessonDefinition(id: "body",     name: "My Body",         description: "Movement-based story — character uses arms, legs, eyes, ears.", emoji: "🧍", ageMin: 2, ageMax: 5),
        ]
    ),
]

// MARK: - LessonRoadmapView

struct LessonRoadmapView: View {
    let child: ChildProfile
    let completedLessonIds: Set<String>
    let onStartLesson: (LessonDefinition) -> Void

    @State private var selectedCategory: LessonCategory? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                // Parchment background
                Theme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        // Header
                        headerSection

                        // Category paths
                        ForEach(lessonCatalogue) { category in
                            categoryPath(category)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hi, \(child.name.components(separatedBy: " ").first ?? child.name)! 👋")
                .font(Theme.titleFont(size: 24))
                .foregroundColor(Theme.ink)

            let done = completedLessonIds.count
            let total = lessonCatalogue.flatMap(\.lessons).count
            Text("\(done) of \(total) lessons completed")
                .font(Theme.bodyFont(size: 15))
                .foregroundColor(Theme.inkMuted)

            // Overall progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.border).frame(height: 8)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(done) / CGFloat(max(total, 1)), height: 8)
                }
            }
            .frame(height: 8)
            .padding(.top, 4)
        }
        .padding(.top, 12)
    }

    // MARK: - Category path (Duolingo-style winding nodes)

    private func categoryPath(_ category: LessonCategory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header pill
            HStack(spacing: 10) {
                Text(category.emoji).font(.system(size: 22))
                Text(category.title)
                    .font(Theme.titleFont(size: 18))
                    .foregroundColor(.white)
                Spacer()
                let done = category.lessons.filter { completedLessonIds.contains($0.id) }.count
                Text("\(done)/\(category.lessons.count)")
                    .font(Theme.bodyFont(size: 14))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(category.color)
            .cornerRadius(16)
            .padding(.bottom, 20)

            // Winding path of nodes
            windingPath(lessons: category.lessons, color: category.color)
        }
    }

    // MARK: - Winding node path

    @ViewBuilder
    private func windingPath(lessons: [LessonDefinition], color: Color) -> some View {
        let zigzag: [CGFloat] = [0.15, 0.5, 0.82, 0.5, 0.15, 0.5, 0.82]

        VStack(spacing: 0) {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { idx, lesson in
                let xFraction = zigzag[idx % zigzag.count]
                let completed = completedLessonIds.contains(lesson.id)
                let unlocked  = isUnlocked(lesson: lesson, in: lessons)

                GeometryReader { geo in
                    ZStack {
                        // Connector line downward (not for last item)
                        if idx < lessons.count - 1 {
                            let nextX = zigzag[(idx + 1) % zigzag.count]
                            connectorLine(from: xFraction, to: nextX, width: geo.size.width,
                                          height: 80, color: color, completed: completed)
                        }

                        // Node button
                        lessonNode(lesson: lesson, color: color,
                                   completed: completed, unlocked: unlocked)
                            .position(x: geo.size.width * xFraction, y: 40)
                    }
                }
                .frame(height: 80)
            }
        }
    }

    @ViewBuilder
    private func lessonNode(lesson: LessonDefinition, color: Color,
                             completed: Bool, unlocked: Bool) -> some View {
        Button {
            if unlocked { onStartLesson(lesson) }
        } label: {
            ZStack {
                // Glow for current (unlocked but not complete)
                if unlocked && !completed {
                    Circle()
                        .fill(color.opacity(0.25))
                        .frame(width: 82, height: 82)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: unlocked)
                }

                Circle()
                    .fill(completed ? color : (unlocked ? color.opacity(0.85) : Theme.card))
                    .frame(width: 68, height: 68)
                    .overlay(
                        Circle()
                            .stroke(completed ? color : (unlocked ? color : Theme.border), lineWidth: 3)
                    )
                    .shadow(color: unlocked ? color.opacity(0.4) : .clear, radius: 8)

                VStack(spacing: 2) {
                    if completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    } else if unlocked {
                        Text(lesson.emoji)
                            .font(.system(size: 26))
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.inkMuted)
                    }
                }
            }
        }
        .disabled(!unlocked)
        .overlay(
            // Label below node
            Text(lesson.name)
                .font(Theme.bodyFont(size: 11))
                .foregroundColor(unlocked ? Theme.ink : Theme.inkMuted)
                .multilineTextAlignment(.center)
                .frame(width: 80)
                .offset(y: 50),
            alignment: .center
        )
    }

    @ViewBuilder
    private func connectorLine(from: CGFloat, to: CGFloat,
                                width: CGFloat, height: CGFloat,
                                color: Color, completed: Bool) -> some View {
        Path { path in
            let startX = width * from
            let endX   = width * to
            let startY: CGFloat = 40
            let endY: CGFloat   = height + 40
            path.move(to: CGPoint(x: startX, y: startY))
            path.addCurve(to: CGPoint(x: endX, y: endY),
                          control1: CGPoint(x: startX, y: startY + height * 0.4),
                          control2: CGPoint(x: endX, y: endY - height * 0.4))
        }
        .stroke(
            completed ? color.opacity(0.7) : color.opacity(0.25),
            style: StrokeStyle(lineWidth: 3, dash: completed ? [] : [6, 5])
        )
    }

    // MARK: - Unlock logic

    private func isUnlocked(lesson: LessonDefinition, in list: [LessonDefinition]) -> Bool {
        guard let idx = list.firstIndex(where: { $0.id == lesson.id }) else { return false }
        if idx == 0 { return true }                                      // first lesson always unlocked
        return completedLessonIds.contains(list[idx - 1].id)            // previous lesson done
    }
}

// MARK: - Preview

#Preview {
    LessonRoadmapView(
        child: ChildProfile(id: "c1", userId: "u1", name: "Lily", age: 5,
                            createdAt: Date(), updatedAt: Date()),
        completedLessonIds: ["count10", "shapes", "vowels"],
        onStartLesson: { _ in }
    )
    .environmentObject(AuthManager())
}
