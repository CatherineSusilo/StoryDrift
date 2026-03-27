import SwiftUI

// MARK: - StoryImageView
//
// Full-screen background image that crossfades smoothly between paragraphs.
//
// How it works:
//   Two image slots — "displayed" (shown at full opacity) and "staged" (loading behind, opacity 0).
//   When imageUrl changes: download -> decode -> stage the new UIImage -> crossfade (swap opacity).
//   During the very first load, or if download fails, a gradient fallback fills the frame.
//   The crossfade duration is 1.5s with easeInOut for a storybook feel.
//   A semi-transparent dark overlay (adjustable via overlayOpacity) sits on top of every image.

struct StoryImageView: View {

    let imageUrl: String?
    var overlayOpacity: Double = 0.45
    var fallback: AnyView = AnyView(
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.04, blue: 0.12),
                     Color(red: 0.08, green: 0.04, blue: 0.18)],
            startPoint: .top, endPoint: .bottom
        )
    )

    @State private var displayedImage: UIImage? = nil
    @State private var stagedImage: UIImage? = nil
    @State private var displayedUrl: String? = nil
    @State private var crossfadeProgress: Double = 0

    var body: some View {
        ZStack {
            fallback.ignoresSafeArea()

            if let img = displayedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .clipped()
                    .opacity(1.0 - crossfadeProgress)
            }

            if let img = stagedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .clipped()
                    .opacity(crossfadeProgress)
            }

            Color.black.opacity(overlayOpacity).ignoresSafeArea()
        }
        .onChange(of: imageUrl) { newUrl in
            guard let newUrl, !newUrl.isEmpty, newUrl != displayedUrl else { return }
            loadAndCrossfade(rawUrl: newUrl)
        }
        .onAppear {
            if let url = imageUrl, !url.isEmpty {
                loadAndCrossfade(rawUrl: url)
            }
        }
    }

    private func loadAndCrossfade(rawUrl: String) {
        guard let url = resolveURL(rawUrl) else { return }
        Task {
            guard let image = await downloadImage(from: url) else { return }
            await MainActor.run {
                stagedImage = image
                crossfadeProgress = 0
                withAnimation(.easeInOut(duration: 1.5)) {
                    crossfadeProgress = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    displayedImage = image
                    displayedUrl = rawUrl
                    stagedImage = nil
                    crossfadeProgress = 0
                }
            }
        }
    }

    private func resolveURL(_ raw: String) -> URL? {
        raw.hasPrefix("http") ? URL(string: raw) : URL(string: "\(Secrets.apiBaseURL)\(raw)")
    }

    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            let (data, _) = try await URLSession.shared.data(for: request)
            return UIImage(data: data)
        } catch {
            print("StoryImageView download failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Convenience initialisers

extension StoryImageView {

    static func bedtime(imageUrl: String?, driftScore: Int) -> StoryImageView {
        var v = StoryImageView(imageUrl: imageUrl)
        v.overlayOpacity = 0.40 + Double(driftScore) / 100.0 * 0.45
        v.fallback = AnyView(LinearGradient(
            colors: [Color(red: 0.03, green: 0.03, blue: 0.12),
                     Color(red: 0.06, green: 0.02, blue: 0.18)],
            startPoint: .top, endPoint: .bottom
        ))
        return v
    }

    static func educational(imageUrl: String?, engagementScore: Int) -> StoryImageView {
        let t = Double(engagementScore) / 100.0
        let top    = Color(red: 0.05 + t * 0.15, green: 0.15 + t * 0.45, blue: 0.35 + t * 0.15)
        let bottom = Color(red: 0.10 + t * 0.10, green: 0.30 + t * 0.30, blue: 0.50)
        var v = StoryImageView(imageUrl: imageUrl)
        v.overlayOpacity = 0.45
        v.fallback = AnyView(LinearGradient(
            colors: [top.opacity(0.8), bottom.opacity(0.4)],
            startPoint: .top, endPoint: .bottom
        ))
        return v
    }
}
