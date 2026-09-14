import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var isMenuEnabled: Bool
    @Published private var enabledKinds: Set<DocumentKind>
    private let preferences: MenuPreferences

    init(preferences: MenuPreferences = .shared) {
        self.preferences = preferences
        isMenuEnabled = preferences.isMenuEnabled
        enabledKinds = Set(preferences.enabledKinds)
    }

    func binding(for kind: DocumentKind) -> Binding<Bool> {
        Binding(
            get: { self.enabledKinds.contains(kind) },
            set: { enabled in
                self.preferences.setEnabled(enabled, for: kind)
                self.enabledKinds = Set(self.preferences.enabledKinds)
            }
        )
    }

    func setMenuEnabled(_ enabled: Bool) {
        preferences.isMenuEnabled = enabled
        isMenuEnabled = enabled
    }

    func enabledCount(in category: FileTypeCategory) -> Int {
        enabledKinds.filter { $0.category == category }.count
    }
}
