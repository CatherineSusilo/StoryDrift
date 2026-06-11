import SwiftUI

struct StoryArchiveView: View {
    @State private var stories: [Story] = []
    @State private var isLoading = true
    @State private var sortBy: SortOption = .date
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var gateManager = ParentalGateManager.shared

    let childId: String

    var sortedStories: [Story] {
        let bedtime = stories.filter { $0.storytellingTone != "educational" }
        switch sortBy {
        case .date:     return bedtime.sorted { $0.generatedAt > $1.generatedAt }
        case .duration: return bedtime.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        case .drift:    return bedtime.sorted { ($0.driftScores.last ?? 0) > ($1.driftScores.last ?? 0) }
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("story archive")
                            .font(Theme.titleFont(size: 28))
                            .foregroundColor(Theme.ink)
                        Text("\(sortedStories.count) stories")
                            .font(Theme.bodyFont(size: 14))
                            .foregroundColor(Theme.inkMuted)
                    }
                    Spacer()
                    Menu {
                        Button(action: { sortBy = .date })     { Label("by date",     systemImage: "calendar") }
                        Button(action: { sortBy = .duration }) { Label("by duration", systemImage: "timer") }
                        Button(action: { sortBy = .drift })    { Label("by drift",    systemImage: "moon.zzz.fill") }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortBy.rawValue.lowercased())
                        }
                        .font(Theme.bodyFont(size: 14))
                        .foregroundColor(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.card)
                        .cornerRadius(Theme.radiusSM)
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                if isLoading {
                    Spacer()
                    ProgressView().tint(Theme.ink)
                    Spacer()
                } else if stories.isEmpty {
                    ArchiveEmptyStateView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(sortedStories) { story in
                                StoryArchiveCard(
                                    story: story,
                                    isParentMode: gateManager.isParentMode,
                                    onDelete: {
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            stories.removeAll { $0.id == story.id }
                                        }
                                    },
                                    onRename: { newTitle in
                                        if let idx = stories.firstIndex(where: { $0.id == story.id }) {
                                            stories[idx].storyTitle = newTitle
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task { await loadStories() }
    }

    private func loadStories() async {
        let token = authManager.accessToken ?? UserDefaults.standard.string(forKey: "accessToken")
        do {
            stories = try await APIService.shared.getStories(childId: childId, token: token)
        } catch {
            print("Failed to load stories: \(error)")
        }
        isLoading = false
    }
}

enum SortOption: String {
    case date = "Date"
    case duration = "Duration"
    case drift = "Drift Score"
}

// MARK: - StoryArchiveCard

struct StoryArchiveCard: View {
    let story: Story
    let isParentMode: Bool
    var onDelete: () -> Void
    var onRename: (String) -> Void

    @EnvironmentObject var authManager: AuthManager
    @State private var showingReplay = false
    @State private var showingRenameSheet = false
    @State private var showDeleteConfirm = false
    @State private var dragOffset: CGFloat = 0

    private let deleteButtonWidth: CGFloat = 80
    private var isRevealed: Bool { dragOffset < -20 }

    var body: some View {
        ZStack(alignment: .trailing) {
            // ── Delete button (revealed when card slides left) ──
            if isParentMode {
                Button {
                    showDeleteConfirm = true
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("delete")
                            .font(Theme.bodyFont(size: 12))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(width: deleteButtonWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .cornerRadius(Theme.radiusMD)
                }
            }

            // ── Card (slides left to reveal delete) ──
            cardContent
                .offset(x: dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .onChanged { value in
                            let tx = value.translation.width
                            let ty = value.translation.height
                            // Only track horizontal-dominant drags
                            guard abs(tx) > abs(ty) else { return }
                            if tx < 0 {
                                // Swiping left — clamp to deleteButtonWidth (or 0 if not parent)
                                let limit: CGFloat = isParentMode ? -deleteButtonWidth : 0
                                dragOffset = max(tx, limit)
                            } else {
                                // Swiping right — slide back toward 0
                                let base = isRevealed ? -deleteButtonWidth : 0
                                dragOffset = min(base + tx, 0)
                            }
                        }
                        .onEnded { value in
                            let tx = value.translation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                if isParentMode && tx < -40 {
                                    dragOffset = -deleteButtonWidth  // snap open
                                } else {
                                    dragOffset = 0                   // snap closed
                                }
                            }
                        }
                )
        }
        .clipped()
        .confirmationDialog(
            "Delete \"\(story.title)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    dragOffset = 0
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
        .fullScreenCover(isPresented: $showingReplay) {
            StoryReplayView(story: story)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showingRenameSheet) {
            RenameStorySheet(currentTitle: story.title) { newTitle in
                await persistRename(newTitle)
                onRename(newTitle)
            }
        }
    }

    // MARK: - Card content

    @ViewBuilder
    private var cardContent: some View {
        Button {
            if isRevealed {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    dragOffset = 0
                }
            } else {
                showingReplay = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    StoryThumbnailView(story: story, size: 64)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(story.title)
                                .font(Theme.bodyFont(size: 17))
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.ink)
                                .lineLimit(2)

                            if isParentMode {
                                Button {
                                    showingRenameSheet = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Theme.inkMuted)
                                        .padding(6)
                                        .background(Theme.accent.opacity(0.25))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(formattedDate)
                            .font(Theme.bodyFont(size: 12))
                            .foregroundColor(Theme.inkMuted)
                    }

                    Spacer()

                    if story.completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.success)
                            .font(.system(size: 22))
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(story.themes, id: \.self) { theme in
                            Text(theme)
                                .font(Theme.bodyFont(size: 12))
                                .foregroundColor(Theme.ink.opacity(0.75))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.3))
                                .cornerRadius(Theme.radiusSM)
                                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(Theme.border, lineWidth: 1))
                        }
                    }
                }

                HStack(spacing: 20) {
                    ArchiveStatItem(icon: "timer",         value: formattedDuration)
                    ArchiveStatItem(icon: "book.pages",    value: "\(story.paragraphs.count) parts")
                    ArchiveStatItem(icon: "moon.zzz.fill", value: "\(finalDrift)% drift")
                }
            }
            .padding(16)
            .parchmentCard(cornerRadius: Theme.radiusMD)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: story.generatedAt)
    }
    private var formattedDuration: String { "\(Int((story.duration ?? 0) / 60)) min" }
    private var finalDrift: Int { Int(story.driftScores.last ?? 0) }

    private func performDelete() async {
        let token = authManager.accessToken ?? UserDefaults.standard.string(forKey: "accessToken") ?? ""
        do {
            try await APIService.shared.deleteStory(storyId: story.id, token: token)
            await MainActor.run { onDelete() }
        } catch {
            print("❌ Delete story failed: \(error)")
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { dragOffset = 0 }
            }
        }
    }

    private func persistRename(_ newTitle: String) async {
        let token = authManager.accessToken ?? UserDefaults.standard.string(forKey: "accessToken") ?? ""
        do {
            _ = try await APIService.shared.renameStory(storyId: story.id, title: newTitle, token: token)
        } catch {
            print("❌ Rename story persist failed: \(error)")
        }
    }
}

// MARK: - RenameStorySheet

struct RenameStorySheet: View {
    let currentTitle: String
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isSaving = false

    init(currentTitle: String, onSave: @escaping (String) async -> Void) {
        self.currentTitle = currentTitle
        self.onSave = onSave
        _title = State(initialValue: currentTitle)
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Theme.border)
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Text("rename story")
                .font(Theme.titleFont(size: 20))
                .foregroundColor(Theme.ink)

            TextField("Story title", text: $title)
                .font(Theme.bodyFont(size: 16))
                .foregroundColor(Theme.ink)
                .padding(12)
                .background(Theme.card)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1.5))
                .padding(.horizontal, 20)
                .submitLabel(.done)
                .onSubmit { Task { await save() } }

            HStack(spacing: 12) {
                Button("cancel") { dismiss() }
                    .font(Theme.bodyFont(size: 16))
                    .foregroundColor(Theme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.card)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1.5))
                    .disabled(isSaving)

                Button("done") { Task { await save() } }
                    .font(Theme.bodyFont(size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(isSaveDisabled ? Theme.inkFaint : Theme.ink)
                    .cornerRadius(8)
                    .disabled(isSaveDisabled)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .presentationDetents([.height(200)])
        .presentationDragIndicator(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving
    }

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        await onSave(trimmed)
        dismiss()
    }
}

// MARK: - Supporting views

struct ArchiveStatItem: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(Theme.inkMuted)
            Text(value).font(Theme.bodyFont(size: 13)).foregroundColor(Theme.ink)
        }
    }
}

struct ArchiveEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 52))
                .foregroundColor(Theme.inkFaint)
            Text("no stories yet")
                .font(Theme.titleFont(size: 24))
                .foregroundColor(Theme.ink)
            Text("start creating magical bedtime stories")
                .font(Theme.bodyFont(size: 15))
                .foregroundColor(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct StoryDetailsView: View {
    let story: Story
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(story.paragraphs.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("part \(i + 1)")
                                    .font(Theme.bodyFont(size: 13))
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.inkMuted)
                                Text(story.paragraphs[i].text)
                                    .font(Theme.bodyFont(size: 16))
                                    .foregroundColor(Theme.ink)
                                    .lineSpacing(4)
                            }
                            .padding(16)
                            .parchmentCard(cornerRadius: Theme.radiusMD)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(story.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done") { dismiss() }
                        .font(Theme.bodyFont(size: 16))
                        .foregroundColor(Theme.ink)
                }
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    StoryArchiveView(childId: "child1")
        .environmentObject(AuthManager())
}
