import SwiftUI

// MARK: - StoryImageView
//
// Full-screen background image that crossfades smoothly between paragraphs.
//
// How it works:
//   • Two image slots — "displayed" (shown at full opacity) and "staged" (loading behind, opacity 0).
//   • When imageUrl changes:  download → decode → stage the new UIImage → crossfade (swap opacity).
//   • During the very first load, or if download fails, a gradient fallback fills the frame.
//   • The crossfade duration is 1.5 s with easeInOut — deliberately slow for a storybook feel.
//   • A semi-transparent dark overlay (adjustable via `overlayOpacity`) sits on top of every image.

struct StoryImageView: View {

    /// The relative-or-absolute URL string from the backend tick response.
    let imageUrl: String?

    /// 0–1 overlay darkness (story text needs to be legible).
    var overlayOpacity: Double = 0.45

    /// Gradient shown before the first image arrives, or on download failure.
    var fallback: AnyView = AnyView(
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.04, blue: 0.12),
                     Color(red: 0.08, green: 0.04, blue: 0.18)],
            startPoint: .top, endPoint: .bottom
        )
    )

    // MARK: - Internal state

    /// The image currently shown at full opacity.
    @State private var displayedImage: UIImage? = nil
    /// The image being cross-faded in.
    @State private var stagedImage: UIImage? = nil
    /// Tracks the URL that displayedImage was loaded from.
    @State private var displayedUrl: String? = nil
    /// 0 = displayed is on top, 1 = staged is cross-faded in fully.
    @State private var crossfadeProgress: Double = 0

    // MARK: - View

    var body: some View {
        ZStack {
            // Layer 1 — gradient fallback (always underneath)
            fallback
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Layer 2 — previously shown image (fades out)
            if let img = displayedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(1.0 - crossfadeProgress)
            }

            // Layer 3 — new incoming image (fades in)
            if let img = stagedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(crossfadeProgress)
            }

            // Layer 4 — dark scrim for text legibility
            Color.black
                .opacity(overlayOpacity)
        }
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: imageUrl) { _, newUrl in
            guard let newUrl, !newUrl.isEmpty, newUrl != displayedUrl else { return }
            loadAndCrossfade(rawUrl: newUrl)
        }
        .onAppear {
            if let url = imageUrl, !url.isEmpty {
                loadAndCrossfade(rawUrl: url)
            }
        }
    }

    // MARK: - Load + crossfade

    private func loadAndCrossfade(rawUrl: String) {
        guard let url = resolveURL(rawUrl) else { return }
        print("🖼 StoryImageView loading: \(rawUrl.prefix(80))")
        Task {
            guard let image = await downloadImage(from: url) else { return }

            await MainActor.run {
                // Stage the new image behind the current one at opacity 0
                stagedImage = image
                crossfadeProgress = 0

                // Crossfade: fade staged in, fade displayed out
                withAnimation(.easeInOut(duration: 1.5)) {
                    crossfadeProgress = 1.0
                }

                // After fade completes, promote staged → displayed and clear staged
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    displayedImage = image
                    displayedUrl = rawUrl
                    stagedImage = nil
                    crossfadeProgress = 0
                }
            }
        }
    }

    // MARK: - URL resolution

    private func resolveURL(_ raw: String) -> URL? {
        if raw.hasPrefix("http") {
            return URL(string: raw)
        }
        return URL(string: "\(Secrets.apiBaseURL)\(raw)")
    }

    // MARK: - Image download

    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            // Use URLCache so repeated views of the same image are instant
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            let (data, _) = try await URLSession.shared.data(for: request)
            return UIImage(data: data)
        } catch {
            print("⚠️ StoryImageView download failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Convenience initialisers

extension StoryImageView {

    /// Bedtime variant — deep indigo night fallback, heavy overlay.
    static func bedtime(imageUrl: String?, driftScore: Int) -> StoryImageView {
        var v = StoryImageView(imageUrl: imageUrl)
        v.overlayOpacity = 0.40 + Double(driftScore) / 100.0 * 0.45
        v.fallback = AnyView(
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.03, blue: 0.12),
                         Color(red: 0.06, green: 0.02, blue: 0.18)],
                startPoint: .top, endPoint: .bottom
            )
        )
        return v
    }

    /// Educational variant — configurable gradient based on engagement score.
    static func educational(imageUrl: String?, engagementScore: Int) -> StoryImageView {
        let t = Double(engagementScore) / 100.0
        let top = Color(
            red: 0.05 + t * 0.15,
            green: 0.15 + t * 0.45,
            blue: 0.35 + t * 0.15
        )
        let bottom = Color(
            red: 0.10 + t * 0.10,
            green: 0.30 + t * 0.30,
            blue: 0.50
        )
        var v = StoryImageView(imageUrl: imageUrl)
        v.overlayOpacity = 0.45
        v.fallback = AnyView(
            LinearGradient(colors: [top.opacity(0.8), bottom.opacity(0.4)],
                           startPoint: .top, endPoint: .bottom)
        )
        return v
    }
}
