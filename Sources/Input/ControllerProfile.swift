import GameController
import UIKit

/// Everything the UI needs to talk about a specific controller in that
/// controller's own language: its name, its button glyphs, its capabilities.
struct ControllerProfile {

    enum Brand: CaseIterable {
        case dualSense
        case dualShock
        case xbox
        case switchPro
        case joyCon
        case siriRemote
        case mfi

        var isPlayStation: Bool { self == .dualSense || self == .dualShock }
    }

    let brand: Brand
    /// Shown in a seat bay, e.g. "DualSense Wireless Controller".
    let displayName: String

    var isRemote: Bool { brand == .siriRemote }

    /// SF Symbol representing the whole device.
    var deviceSymbol: String {
        isRemote ? "av.remote.fill" : "gamecontroller.fill"
    }

    /// Compact label for chips and rails, where the full marketing name is too
    /// long to sit alongside anything else.
    var shortName: String {
        switch brand {
        case .dualSense: return "DualSense"
        case .dualShock: return "DualShock"
        case .xbox: return "Xbox Controller"
        case .switchPro: return "Switch Pro"
        case .joyCon: return "Joy-Con"
        case .siriRemote: return "Siri Remote"
        case .mfi: return displayName
        }
    }

    // MARK: - Buttons
    //
    // These describe the *physical* button behind each logical action, in the
    // brand's own vocabulary. GCExtendedGamepad is position-based, so buttonA is
    // always the south face button — Cross on PlayStation, A on Xbox. The Siri
    // Remote is the odd one out: GCMicroGamepad gives only buttonA (click the
    // touch surface) and buttonX (Play/Pause), and no third action button.

    var confirmSymbol: String {
        switch brand {
        case .dualSense, .dualShock: return "xmark.circle.fill"
        case .siriRemote: return "circle.circle.fill"
        default: return "a.circle.fill"
        }
    }

    var confirmFallback: String {
        switch brand {
        case .dualSense, .dualShock: return "X"
        case .siriRemote: return "OK"
        default: return "A"
        }
    }

    var confirmName: String {
        switch brand {
        case .dualSense, .dualShock: return "Cross"
        case .siriRemote: return "Select"
        default: return "A"
        }
    }

    var backSymbol: String {
        switch brand {
        case .dualSense, .dualShock: return "circle.circle.fill"
        case .siriRemote: return "playpause.circle.fill"
        default: return "b.circle.fill"
        }
    }

    var backFallback: String {
        switch brand {
        case .dualSense, .dualShock: return "O"
        case .siriRemote: return "PLAY/PAUSE"
        default: return "B"
        }
    }

    var backName: String {
        switch brand {
        case .dualSense, .dualShock: return "Circle"
        case .siriRemote: return "Play/Pause"
        default: return "B"
        }
    }

    // GCExtendedGamepad is position-based, so buttonX is always the *west* face
    // button and buttonY the *north* one. That is Square/Triangle on PlayStation
    // and, on Nintendo layouts, Y/X — the opposite of the letters the pad prints
    // where an Xbox pad would say X/Y.

    var secondarySymbol: String {
        switch brand {
        case .dualSense, .dualShock: return "square.circle.fill"
        case .switchPro, .joyCon: return "y.circle.fill"
        default: return "x.circle.fill"
        }
    }

    var secondaryFallback: String {
        switch brand {
        case .dualSense, .dualShock: return "SQ"
        case .switchPro, .joyCon: return "Y"
        default: return "X"
        }
    }

    var secondaryName: String {
        switch brand {
        case .dualSense, .dualShock: return "Square"
        case .switchPro, .joyCon: return "Y"
        default: return "X"
        }
    }

    /// The Menu button, which tvOS also delivers as a UIPress. It is Options on
    /// PlayStation, Menu on Xbox, Plus on Switch, and the back button on the
    /// Siri Remote — never a generic chevron, which names no physical button.
    var menuSymbol: String {
        switch brand {
        case .siriRemote: return "chevron.left.circle.fill"
        case .switchPro: return "plus.circle.fill"
        default: return "line.3.horizontal.circle.fill"
        }
    }

    var menuFallback: String {
        switch brand {
        case .dualSense, .dualShock: return "OPTIONS"
        case .switchPro: return "+"
        default: return "MENU"
        }
    }

    var menuName: String {
        switch brand {
        case .dualSense, .dualShock: return "Options"
        case .switchPro: return "Plus"
        case .siriRemote: return "Menu"
        default: return "Menu"
        }
    }

    /// The "seat a CPU here" shortcut. Absent on the Siri Remote.
    var hasTertiaryButton: Bool { brand != .siriRemote }

    var tertiarySymbol: String {
        switch brand {
        case .dualSense, .dualShock: return "triangle.circle.fill"
        case .switchPro, .joyCon: return "x.circle.fill"
        default: return "y.circle.fill"
        }
    }

    var tertiaryFallback: String {
        switch brand {
        case .dualSense, .dualShock: return "TRI"
        case .switchPro, .joyCon: return "X"
        default: return "Y"
        }
    }

    /// How this device steers a paddle, used for the lobby's control hint.
    var steeringHint: String {
        switch brand {
        case .siriRemote: return "Slide your thumb on the touch surface"
        case .joyCon: return "Stick or D-pad"
        default: return "Left stick or D-pad"
        }
    }

    // MARK: - Detection

    static func detect(_ controller: GCController) -> ControllerProfile {
        let haystack = (controller.productCategory + " "
                        + (controller.vendorName ?? "")).lowercased()

        func has(_ needles: String...) -> Bool {
            needles.contains { haystack.contains($0) }
        }

        let brand: Brand
        if has("dualsense", "ps5") {
            brand = .dualSense
        } else if has("dualshock", "ps4", "playstation") {
            brand = .dualShock
        } else if has("xbox") {
            brand = .xbox
        } else if has("switch pro", "switchpro", "nintendo") {
            brand = .switchPro
        } else if has("joy-con", "joycon") {
            brand = .joyCon
        } else if has("siri remote", "remote") || controller.extendedGamepad == nil {
            brand = .siriRemote
        } else {
            brand = .mfi
        }

        return ControllerProfile(brand: brand,
                                 displayName: controller.vendorName ?? defaultName(brand))
    }

    /// Used when a device reports no vendor name, and by the debug harness.
    static func defaultName(_ brand: Brand) -> String {
        switch brand {
        case .dualSense: return "DualSense Wireless Controller"
        case .dualShock: return "DualShock 4 Wireless Controller"
        case .xbox: return "Xbox Wireless Controller"
        case .switchPro: return "Switch Pro Controller"
        case .joyCon: return "Joy-Con"
        case .siriRemote: return "Siri Remote"
        case .mfi: return "Game Controller"
        }
    }
}
