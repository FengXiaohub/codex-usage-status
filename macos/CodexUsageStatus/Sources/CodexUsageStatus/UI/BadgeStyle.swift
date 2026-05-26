import Foundation

enum BadgeStyle: String, CaseIterable {
    case doubleRing
    case largeReadout

    private static let defaultsKey = "BadgeStyle"

    var menuTitle: String {
        switch self {
        case .doubleRing:
            return "Double Ring"
        case .largeReadout:
            return "Large Readout"
        }
    }

    static func load() -> BadgeStyle {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let style = BadgeStyle(rawValue: rawValue) else {
            return .doubleRing
        }
        return style
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
