import Foundation

/// The app and extension must use the same certificate-authorized group.
final class MenuPreferences {
    static let suiteName = "QN24ZH7M6W.GMX.MoreMenu"
    static let finderMenuEnabledKey = "finderMenuEnabled"
    static let enabledDocumentKeysKey = "enabledDocumentKeys"

    static let shared: MenuPreferences = {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not initialize MoreMenu's shared preferences")
        }
        return MenuPreferences(defaults: defaults)
    }()

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var isMenuEnabled: Bool {
        get {
            defaults.object(forKey: Self.finderMenuEnabledKey) == nil
                ? true : defaults.bool(forKey: Self.finderMenuEnabledKey)
        }
        set { defaults.set(newValue, forKey: Self.finderMenuEnabledKey) }
    }

    var enabledKinds: [DocumentKind] {
        guard let stored = defaults.stringArray(forKey: Self.enabledDocumentKeysKey) else {
            return DocumentKind.allCases.filter(\.defaultEnabled)
        }
        let keys = Set(stored)
        return DocumentKind.allCases.filter { keys.contains($0.rawValue) }
    }

    var activeKinds: [DocumentKind] { isMenuEnabled ? enabledKinds : [] }

    func setEnabled(_ enabled: Bool, for kind: DocumentKind) {
        var selected = Set(enabledKinds)
        if enabled { selected.insert(kind) } else { selected.remove(kind) }
        defaults.set(DocumentKind.allCases.filter { selected.contains($0) }.map(\.rawValue),
                     forKey: Self.enabledDocumentKeysKey)
    }

    /// Installer supplies the old preferences; the sandbox never opens the old group.
    /// Decode the whole payload before writing and preserve choices already made here.
    @discardableResult
    func importLegacySettings(_ data: Data) throws -> Bool {
        let settings = try JSONDecoder().decode(LegacySettings.self, from: data)
        var changed = false
        if defaults.object(forKey: Self.finderMenuEnabledKey) == nil,
           let enabled = settings.finderMenuEnabled {
            isMenuEnabled = enabled
            changed = true
        }
        if defaults.object(forKey: Self.enabledDocumentKeysKey) == nil,
           let keys = settings.enabledDocumentKeys {
            let selected = Set(keys)
            defaults.set(DocumentKind.allCases.filter { selected.contains($0.rawValue) }.map(\.rawValue),
                         forKey: Self.enabledDocumentKeysKey)
            changed = true
        }
        return changed
    }

    private struct LegacySettings: Decodable {
        let finderMenuEnabled: Bool?
        let enabledDocumentKeys: [String]?
    }
}
