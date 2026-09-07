import SpriteKit

/// Screens the app can show. Payloads travel with the case so scenes stay free
/// of shared mutable state.
enum Route {
    case boot
    case lobby(returnToMenu: Bool)
    case menu
    case match(MatchConfig)
    case result(MatchResult, MatchConfig)
    case achievements
    case settings
    case pairingHelp
}

/// Owns scene presentation. Scenes ask the router to move; they never build
/// each other directly.
final class Router {

    static let shared = Router()
    weak var view: SKView?

    private init() {}

    func go(_ route: Route, transition: SKTransition? = nil) {
        guard let view else { return }
        let scene = makeScene(route)
        scene.size = Theme.sceneSize
        scene.scaleMode = .aspectFit
        let move = transition ?? SKTransition.fade(with: Theme.background,
                                                  duration: Theme.transition)
        move.pausesIncomingScene = false
        view.presentScene(scene, transition: move)
    }

    private func makeScene(_ route: Route) -> BaseScene {
        switch route {
        case .boot:
            return BootScene(size: Theme.sceneSize)
        case .lobby(let returnToMenu):
            return LobbyScene(size: Theme.sceneSize, returnToMenu: returnToMenu)
        case .menu:
            return MenuScene(size: Theme.sceneSize)
        case .match(let config):
            return MatchScene(size: Theme.sceneSize, config: config)
        case .result(let result, let config):
            return ResultScene(size: Theme.sceneSize, result: result, config: config)
        case .achievements:
            return AchievementsScene(size: Theme.sceneSize)
        case .settings:
            return SettingsScene(size: Theme.sceneSize)
        case .pairingHelp:
            return PairingHelpScene(size: Theme.sceneSize)
        }
    }
}
