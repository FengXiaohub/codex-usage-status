import Foundation

enum BadgeStyle: String, CaseIterable {
    case doubleRing
    case largeReadout
    case quotaAndResetTimes

    private static let defaultsKey = "BadgeStyle"

    var menuTitle: String {
        menuTitle(chinese: false)
    }

    func menuTitle(chinese: Bool) -> String {
        switch self {
        case .doubleRing:
            return chinese ? "双圆环" : "Double Ring"
        case .largeReadout:
            return chinese ? "大字号读数" : "Large Readout"
        case .quotaAndResetTimes:
            return chinese ? "配额与重置时间" : "Quota & Reset Times"
        }
    }

    static func load() -> BadgeStyle {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let style = BadgeStyle(rawValue: rawValue) else {
            return .quotaAndResetTimes
        }
        return style
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

struct QuotaVisibility: Equatable, Sendable {
    private static let hiddenDefaultsKey = "HiddenQuotaProviders"

    private(set) var hidden: Set<TokenProvider>

    init(hidden: Set<TokenProvider> = []) {
        // Keep at least one column visible so the menu-bar status item never disappears.
        if hidden.count >= TokenProvider.allCases.count {
            self.hidden = []
        } else {
            self.hidden = hidden
        }
    }

    var visibleProviders: [TokenProvider] {
        TokenProvider.allCases.filter { !hidden.contains($0) }
    }

    var includesCodex: Bool {
        !hidden.contains(.codex)
    }

    var includesAntigravity: Bool {
        !hidden.contains(.gemini) || !hidden.contains(.claudeGpt)
    }

    func isVisible(_ provider: TokenProvider) -> Bool {
        !hidden.contains(provider)
    }

    func canHide(_ provider: TokenProvider) -> Bool {
        !isVisible(provider) || visibleProviders.count > 1
    }

    @discardableResult
    mutating func toggle(_ provider: TokenProvider) -> Bool {
        if hidden.contains(provider) {
            hidden.remove(provider)
            return true
        }
        guard visibleProviders.count > 1 else {
            return false
        }
        hidden.insert(provider)
        return true
    }

    static func load() -> QuotaVisibility {
        let raw = UserDefaults.standard.stringArray(forKey: hiddenDefaultsKey) ?? []
        let parsed = Set(raw.compactMap(TokenProvider.init(rawValue:)))
        return QuotaVisibility(hidden: parsed)
    }

    func save() {
        let raw = TokenProvider.allCases.filter { hidden.contains($0) }.map(\.rawValue)
        UserDefaults.standard.set(raw, forKey: Self.hiddenDefaultsKey)
    }
}
