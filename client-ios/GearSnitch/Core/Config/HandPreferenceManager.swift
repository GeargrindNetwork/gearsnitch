import Foundation
import SwiftUI

enum HandSide: String, Codable {
    case left
    case right
}

@MainActor
final class HandPreferenceManager: ObservableObject {
    static let shared = HandPreferenceManager()

    @Published var menuSide: HandSide {
        didSet {
            UserDefaults.standard.set(menuSide.rawValue, forKey: "gs_menu_side")
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "gs_menu_side") ?? "right"
        menuSide = HandSide(rawValue: stored) ?? .right
    }

    var isMenuOnLeft: Bool { menuSide == .left }
}
