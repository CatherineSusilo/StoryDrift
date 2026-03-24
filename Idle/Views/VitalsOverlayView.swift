import SwiftUI

#if canImport(SmartSpectraSwiftSDK)
import SmartSpectraSwiftSDK
#endif

// MARK: - VitalsOverlayView
/// A fully transparent overlay that activates SmartSpectra headless vitals tracking.
/// Drop this as an `.overlay` or inside a `ZStack` on StoryPlaybackView.
/// It has zero visual footprint — the camera runs silently in the background.
struct VitalsOverlayView: View {
    @ObservedObject var tracker: StoryVitalsTracker
    @EnvironmentObject var vitalsManager: VitalsManager

    let storyId: String
    let childId: String

    var body: some View {
        // Completely transparent — no UI chrome, just lifecycle hooks
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                tracker.startTracking(
                    storyId: storyId,
                    childId: childId,
                    vitalsManager: vitalsManager
                )
            }
            .onDisappear {
                tracker.stopTracking()
            }
    }
}

// MARK: - Preview helper
#if DEBUG
struct VitalsOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            Text("Story would be here")
                .foregroundColor(.white)
            VitalsOverlayView(
                tracker: StoryVitalsTracker(),
                storyId: "preview-story",
                childId: "preview-child"
            )
        }
        .environmentObject(VitalsManager())
    }
}
#endif
