import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    /// Force landscape on iPhone; allow portrait + landscape on iPad.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [.portrait, .landscapeLeft, .landscapeRight]
        }
        // iPhone — landscape only
        return [.landscapeLeft, .landscapeRight]
    }
}
