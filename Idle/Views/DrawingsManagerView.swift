import SwiftUI
import PhotosUI

/// Ported from DrawingsManager.tsx — lets parents upload and manage a child's drawings
/// that can be used as inspiration for story image generation.
struct DrawingsManagerView: View {
    @EnvironmentObject var authManager: AuthManager
    let onBack: () -> Void

    @State private var children: [ChildProfile] = []
    @State private var selectedChild: ChildProfile?
    @State private var drawings: [ChildDrawing] = []
    @State private var loading = true
    @State private var uploading = false
    @State private var showPhotoPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var drawingToDelete: ChildDrawing?
    @State private var showDeleteAlert = false
    @State private var selectedDrawingForPreview: ChildDrawing? = nil

    // MARK: - Parchment palette
    private let bg        = Color(red: 0.894, green: 0.835, blue: 0.718)
    private let cardBg    = Color(red: 0.980, green: 0.961, blue: 0.922)
    private let borderClr = Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.28)
    private let btnBg     = Color(red: 0.824, green: 0.706, blue: 0.549).opacity(0.4)
    private let ink       = Color(red: 0.078, green: 0.059, blue: 0.039)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            if loading {
                loadingView
            } else {
                mainContent
            }

            // ── Full-screen drawing preview ──────────────────────────────
            if let preview = selectedDrawingForPreview {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { selectedDrawingForPreview = nil } }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    // Close button — top right
                    HStack {
                        Spacer()
                        Button {
                            withAnimation { selectedDrawingForPreview = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(Color.white.opacity(0.2)))
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 16)
                    }

                    Spacer()

                    // Image
                    Group {
                        if let url = preview.imageUrl, let parsed = URL(string: url) {
                            AsyncImage(url: parsed) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFit()
                                case .empty:
                                    ProgressView().tint(.white)
                                default:
                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                        } else if let data = preview.imageData, let uiImg = UIImage(data: data) {
                            Image(uiImage: uiImg).resizable().scaledToFit()
                        } else {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
                    .padding(.horizontal, 24)

                    Spacer()

                    // Caption
                    Text(preview.name)
                        .font(.custom("PatrickHand-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedDrawingForPreview == nil)
        .navigationBarHidden(true)
        .task { await loadChildren() }
        .onAppear {
            // Refresh drawings when view appears (picks up new minigame drawings)
            if let childId = selectedChild?.id {
                print("🔄 DrawingsManagerView appeared - refreshing drawings")
                
                // Debug: Show all drawings keys in UserDefaults
                let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
                let drawingKeys = allKeys.filter { $0.hasPrefix("drawings_") }
                print("🔍 Found \(drawingKeys.count) drawings keys in UserDefaults:")
                for key in drawingKeys.sorted() {
                    if let data = UserDefaults.standard.data(forKey: key) {
                        print("   - \(key): \(data.count) bytes")
                    }
                }
                
                loadDrawings(childId: childId)
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickerItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: pickerItems) { _ in
            Task { await uploadPickedPhotos() }
        }
        .alert("Delete this drawing?", isPresented: $showDeleteAlert, presenting: drawingToDelete) { drawing in
            Button("Delete", role: .destructive) { performDelete(drawing) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Loading State
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(ink)
                .scaleEffect(1.4)
            Text("opening gallery…")
                .font(.custom("PatrickHand-Regular", size: 20))
                .foregroundColor(ink.opacity(0.7))
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(ink)
                    }
                    Spacer()
                    Text("drawings collection")
                        .font(.custom("IndieFlower-Regular", size: 30))
                        .foregroundColor(ink)
                    Spacer()
                    Color.clear.frame(width: 24)
                }
                .padding(.top, 20)

                // Child Selector
                if children.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(children) { child in
                                childTabButton(child)
                            }
                        }
                    }
                }

                // Upload Button
                Button {
                    showPhotoPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: uploading ? "arrow.triangle.2.circlepath" : "arrow.up.doc")
                            .font(.system(size: 16))
                        Text(uploading ? "uploading…" : "upload drawing")
                            .font(.custom("PatrickHand-Regular", size: 18))
                            .fontWeight(.bold)
                    }
                    .foregroundColor(ink.opacity(0.85))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(btnBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderClr, lineWidth: 2)
                    )
                    .cornerRadius(6)
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                }
                .disabled(uploading || selectedChild == nil)

                // Grid or Empty State
                if drawings.isEmpty {
                    emptyState
                } else {
                    drawingsGrid
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Child Tab Button
    @ViewBuilder
    private func childTabButton(_ child: ChildProfile) -> some View {
        let isActive = selectedChild?.id == child.id
        Button {
            selectedChild = child
            loadDrawings(childId: child.id)
        } label: {
            Text(child.name)
                .font(.custom("PatrickHand-Regular", size: 17))
                .fontWeight(isActive ? .bold : .regular)
                .foregroundColor(isActive ? ink : ink.opacity(0.65))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(isActive ? Color(red: 0.824, green: 0.706, blue: 0.549).opacity(0.4) : cardBg.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? borderClr.opacity(1.4) : borderClr.opacity(0.5),
                                lineWidth: isActive ? 2 : 1)
                )
                .cornerRadius(6)
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundColor(ink.opacity(0.25))
            Text("no drawings yet")
                .font(.custom("PatrickHand-Regular", size: 20))
                .foregroundColor(ink.opacity(0.55))
            Text("upload their artwork to inspire stories")
                .font(.custom("PatrickHand-Regular", size: 15))
                .foregroundColor(ink.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(48)
        .background(cardBg.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderClr, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
        )
        .cornerRadius(8)
    }

    // MARK: - Drawings Grid
    private var drawingsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(drawings) { drawing in
                drawingCard(drawing)
            }
        }
    }

    @ViewBuilder
    private func drawingCard(_ drawing: ChildDrawing) -> some View {
        ZStack(alignment: .topTrailing) {
            // Tap anywhere on the card (except delete button) to preview
            Button { selectedDrawingForPreview = drawing } label: {
                VStack(alignment: .leading, spacing: 6) {
                // Display image from cloud URL or legacy data
                if let imageUrl = drawing.imageUrl {
                    // Cloud-stored image
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 140)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 140)
                                .clipped()
                        case .failure:
                            Image(systemName: "photo.fill")
                                .font(.system(size: 40))
                                .foregroundColor(ink.opacity(0.3))
                                .frame(height: 140)
                                .frame(maxWidth: .infinity)
                                .background(cardBg.opacity(0.5))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(borderClr.opacity(0.5), lineWidth: 1)
                    )
                } else if let imageData = drawing.imageData, let uiImage = UIImage(data: imageData) {
                    // Legacy local image data
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(borderClr.opacity(0.5), lineWidth: 1)
                        )
                } else {
                    // Fallback placeholder
                    Image(systemName: "photo.fill")
                        .font(.system(size: 40))
                        .foregroundColor(ink.opacity(0.3))
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .background(cardBg.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(borderClr.opacity(0.5), lineWidth: 1)
                        )
                }
                
                // Display lesson emoji + name if from minigame
                if drawing.source == "minigame", let emoji = drawing.lessonEmoji, let lessonName = drawing.lessonName {
                    HStack(spacing: 4) {
                        Text(emoji)
                            .font(.system(size: 12))
                        Text(lessonName)
                            .font(.custom("PatrickHand-Regular", size: 11))
                            .foregroundColor(ink.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                
                Text(drawing.name)
                    .font(.custom("PatrickHand-Regular", size: 14))
                    .foregroundColor(ink.opacity(0.75))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(drawing.uploadedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.custom("PatrickHand-Regular", size: 12))
                }
                .foregroundColor(ink.opacity(0.45))
            }
            .padding(8)
            .background(cardBg.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderClr, lineWidth: 2)
            )
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 2)
            }  // end Button label
            .buttonStyle(.plain)

            // Delete button
            Button {
                drawingToDelete = drawing
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(7)
                    .background(Color(red: 0.7, green: 0.31, blue: 0.31).opacity(0.85))
                    .cornerRadius(4)
            }
            .padding(6)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    // MARK: - Data Persistence (UserDefaults, keyed per child)
    private func drawingsKey(childId: String) -> String { "drawings_\(childId)" }

    private func loadDrawings(childId: String) {
        print("📂 Loading drawings for child \(childId)")
        
        // Force synchronization to get latest data
        UserDefaults.standard.synchronize()
        
        guard let data = UserDefaults.standard.data(forKey: drawingsKey(childId: childId)) else {
            print("ℹ️ No drawings data found for key: drawings_\(childId)")
            drawings = []
            // Fetch from backend in case there are cloud drawings
            Task {
                await fetchDrawingsFromBackend(childId: childId)
            }
            return
        }
        
        do {
            let decoded = try JSONDecoder().decode([ChildDrawing].self, from: data)
            drawings = decoded
            print("✅ Loaded \(decoded.count) drawings from local storage")
            
            // Also fetch from backend to get any new cloud drawings
            Task {
                await fetchDrawingsFromBackend(childId: childId)
            }
        } catch {
            print("❌ Failed to decode drawings: \(error)")
            drawings = []
            // Try fetching from backend
            Task {
                await fetchDrawingsFromBackend(childId: childId)
            }
        }
    }

    private func saveDrawings(childId: String) {
        print("💾 Saving \(drawings.count) drawings for child \(childId)")
        
        do {
            let data = try JSONEncoder().encode(drawings)
            UserDefaults.standard.set(data, forKey: drawingsKey(childId: childId))
            
            // Force synchronization
            let synced = UserDefaults.standard.synchronize()
            if synced {
                print("✅ Drawings saved and synchronized to UserDefaults")
            } else {
                print("⚠️ synchronize() returned false")
            }
            
            // Sync to MongoDB in background
            Task {
                await syncDrawingsToBackend(childId: childId)
            }
        } catch {
            print("❌ Failed to encode drawings: \(error)")
        }
    }

    private func performDelete(_ drawing: ChildDrawing) {
        withAnimation {
            drawings.removeAll { $0.id == drawing.id }
        }
        if let cid = selectedChild?.id {
            saveDrawings(childId: cid)
            
            // Delete from backend too
            Task {
                await deleteDrawingFromBackend(drawingId: drawing.id)
            }
        }
    }
    
    // MARK: - Backend Sync
    
    /// Fetch drawings from MongoDB backend (including minigame drawings)
    @MainActor
    private func fetchDrawingsFromBackend(childId: String) async {
        guard let token = authManager.accessToken else {
            print("⚠️ No auth token - skipping backend fetch")
            return
        }
        
        print("☁️ Fetching drawings from backend for child \(childId)...")
        
        do {
            let backendDrawings = try await APIService.shared.getDrawings(childId: childId, token: token)
            print("✅ Fetched \(backendDrawings.count) drawings from backend")
            
            // Merge with local drawings (prefer backend as source of truth)
            var mergedDrawings: [ChildDrawing] = []
            var seenIds = Set<String>()
            
            // Add backend drawings first
            for backendDrawing in backendDrawings {
                if !seenIds.contains(backendDrawing.id) {
                    mergedDrawings.append(backendDrawing)
                    seenIds.insert(backendDrawing.id)
                }
            }
            
            // Add local-only drawings that aren't in backend yet
            for localDrawing in drawings {
                if !seenIds.contains(localDrawing.id) {
                    mergedDrawings.append(localDrawing)
                    seenIds.insert(localDrawing.id)
                }
            }
            
            // Sort by upload date (newest first)
            mergedDrawings.sort { $0.uploadedAt > $1.uploadedAt }
            
            drawings = mergedDrawings
            print("✅ Merged drawings: \(mergedDrawings.count) total")
            
            // Save merged list back to local storage
            saveDrawings(childId: childId)
        } catch {
            print("❌ Failed to fetch drawings from backend: \(error)")
        }
    }
    
    /// Sync all local drawings to MongoDB backend
    private func syncDrawingsToBackend(childId: String) async {
        guard let token = authManager.accessToken else {
            print("⚠️ No auth token - skipping backend sync")
            return
        }
        
        print("☁️ Syncing local drawings to MongoDB...")
        
        // Only sync drawings that have imageData (not already in cloud)
        let localOnlyDrawings = drawings.filter { $0.imageUrl == nil && $0.imageData != nil }
        
        guard !localOnlyDrawings.isEmpty else {
            print("ℹ️ No local-only drawings to sync")
            return
        }
        
        // Convert ChildDrawing to DrawingUploadRequest
        let uploadRequests = localOnlyDrawings.compactMap { drawing -> DrawingUploadRequest? in
            guard let imageData = drawing.imageData else { return nil }
            return DrawingUploadRequest(
                childId: childId,
                name: drawing.name,
                imageData: imageData.base64EncodedString(),
                uploadedAt: drawing.uploadedAt,
                source: drawing.source ?? (drawing.name.contains("🔢") || drawing.name.contains("📚") ||
                        drawing.name.contains("🔤") ? "minigame" : "manual_upload"),
                lessonName: drawing.lessonName ?? extractLessonName(from: drawing.name),
                lessonEmoji: drawing.lessonEmoji ?? extractLessonEmoji(from: drawing.name)
            )
        }
        
        do {
            let result = try await APIService.shared.uploadDrawingsBatch(
                childId: childId,
                drawings: uploadRequests,
                token: token
            )
            print("✅ Backend sync complete: \(result.success) uploaded to R2, \(result.failed) failed")
            if let errors = result.errors, !errors.isEmpty {
                print("⚠️ Sync errors: \(errors.joined(separator: ", "))")
            }
        } catch {
            print("❌ Backend sync failed: \(error)")
        }
    }
    
    /// Delete drawing from MongoDB backend
    private func deleteDrawingFromBackend(drawingId: String) async {
        guard let token = authManager.accessToken else { return }
        
        do {
            try await APIService.shared.deleteDrawing(drawingId: drawingId, token: token)
            print("✅ Drawing deleted from backend: \(drawingId)")
        } catch {
            print("⚠️ Failed to delete from backend: \(error)")
        }
    }
    
    // Helper to extract lesson info from drawing name
    private func extractLessonName(from name: String) -> String? {
        // Format: "🔢 Lesson Name - timestamp"
        let components = name.components(separatedBy: " - ")
        guard let first = components.first else { return nil }
        // Remove emoji
        let withoutEmoji = first.drop(while: { $0.unicodeScalars.first?.properties.isEmoji == true })
        return withoutEmoji.trimmingCharacters(in: .whitespaces)
    }
    
    private func extractLessonEmoji(from name: String) -> String? {
        // Get first character if it's an emoji
        guard let first = name.first,
              first.unicodeScalars.first?.properties.isEmoji == true else { return nil }
        return String(first)
    }

    // MARK: - Loading
    private func loadChildren() async {
        guard let token = authManager.accessToken else { loading = false; return }
        do {
            let fetched = try await APIService.shared.getChildren(token: token)
            await MainActor.run {
                children = fetched
                selectedChild = fetched.first
                if let first = fetched.first {
                    loadDrawings(childId: first.id)
                }
                loading = false
            }
        } catch {
            print("DrawingsManagerView: failed to load children — \(error)")
            await MainActor.run { loading = false }
        }
    }

    // MARK: - Upload (PhotosUI → Data → ChildDrawing)
    private func uploadPickedPhotos() async {
        guard let cid = selectedChild?.id, !pickerItems.isEmpty else { return }
        await MainActor.run { uploading = true }

        var newDrawings: [ChildDrawing] = []
        for item in pickerItems {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let name = "drawing_\(Int(Date().timeIntervalSince1970)).jpg"
            newDrawings.append(ChildDrawing(name: name, imageData: data, uploadedAt: Date()))
        }

        await MainActor.run {
            withAnimation {
                drawings.append(contentsOf: newDrawings)
            }
            saveDrawings(childId: cid)
            pickerItems = []
            uploading = false
        }
    }
}

#Preview {
    DrawingsManagerView(onBack: {})
        .environmentObject(AuthManager())
}
