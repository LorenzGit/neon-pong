import SpriteKit
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Bring the shared services up before the first scene asks for them.
        SoundEngine.shared.start()
        ControllerHub.shared.start()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Pausing the view stops the update loop, so a match cannot advance while
        // the user is in Control Center or a system dialog.
        setPaused(true)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        setPaused(false)
    }

    private func setPaused(_ paused: Bool) {
        (window?.rootViewController?.view as? SKView)?.isPaused = paused
    }
}
