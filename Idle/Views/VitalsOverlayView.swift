import SwiftUI

// MARK: - VitalsOverlayView
/// Retained for compatibility. Tracking is now driven directly by StoryPlaybackView's
/// startStory() / stopStory() methods rather than view lifecycle, ensuring it fires
/// for both normal and DEBUG storytime modes.
struct VitalsOverlayView: View {
    @ObservedObject var tracker: StoryVitalsTracker
    @EnvironmentObject var vitalsManager: VitalsManager

    let storyId: String
    let childId: String

    var body: some View {
        // No UI — tracking is controlled by StoryPlaybackView
        Color.clear.frame(width: 0, height: 0)
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
