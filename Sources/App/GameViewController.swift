import SpriteKit
import UIKit

/// Hosts the SpriteKit view and routes the Menu button. Everything else lives
/// in scenes.
final class GameViewController: UIViewController {

    private var skView: SKView { view as! SKView }
    /// Set when the scene swallowed a Menu press, so the matching release is
    /// swallowed too and never reaches the system twice.
    private var consumedMenuPress = false

    override func loadView() {
        let view = SKView(frame: UIScreen.main.bounds)
        view.backgroundColor = Theme.background
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        skView.ignoresSiblingOrder = true
        // Off by default; the debug overlay is enabled from Settings when needed.
        skView.showsFPS = false
        skView.showsNodeCount = false
        skView.preferredFramesPerSecond = 60

        Router.shared.view = skView
        var route = Route.boot
        #if DEBUG
        if let override = DebugHarness.startRoute() { route = override }
        DebugHarness.startScriptIfRequested()
        #endif
        Router.shared.go(route, transition: SKTransition.fade(withDuration: 0.01))
    }

    override var preferredUserInterfaceStyle: UIUserInterfaceStyle { .dark }

    // MARK: - Menu button

    /// tvOS delivers the Menu / Back button as a UIPress. Consuming it keeps the
    /// user in the app; passing it up the chain at the root screen is what makes
    /// "press Menu at the main screen to leave" behave the way the platform
    /// expects.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard presses.contains(where: { $0.type == .menu }) else {
            super.pressesBegan(presses, with: event)
            return
        }
        if let scene = skView.scene as? BaseScene, scene.requestMenuButton() {
            consumedMenuPress = true
            return
        }
        consumedMenuPress = false
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // The scene already acted on `began`; swallow the matching end so the
        // system does not also process it.
        if presses.contains(where: { $0.type == .menu }), consumedMenuPress {
            consumedMenuPress = false
            return
        }
        super.pressesEnded(presses, with: event)
    }
}
