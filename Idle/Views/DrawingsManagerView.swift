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
        }
        .navigationBarHidden(true)
        .task { await loadChildren() }
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
            VStack(alignment: .leading, spacing: 6) {
                if let uiImage = UIImage(data: drawing.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(borderClr.opacity(0.5), lineWidth: 1)
                        )
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
        guard let data = UserDefaults.standard.data(forKey: drawingsKey(childId: childId)),
              let decoded = try? JSONDecoder().decode([ChildDrawing].self, from: data) else {
            drawings = []
            return
        }
        drawings = decoded
    }

    private func saveDrawings(childId: String) {
        guard let data = try? JSONEncoder().encode(drawings) else { return }
        UserDefaults.standard.set(data, forKey: drawingsKey(childId: childId))
    }

    private func performDelete(_ drawing: ChildDrawing) {
        withAnimation {
            drawings.removeAll { $0.id == drawing.id }
        }
        if let cid = selectedChild?.id { saveDrawings(childId: cid) }
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

// MARK: - ChildDrawing Model (local persistence only)
struct ChildDrawing: Codable, Identifiable {
    let id: String
    let name: String
    let imageData: Data
    let uploadedAt: Date

    init(id: String = UUID().uuidString, name: String, imageData: Data, uploadedAt: Date) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.uploadedAt = uploadedAt
    }
}

#Preview {
    DrawingsManagerView(onBack: {})
        .environmentObject(AuthManager())
}
