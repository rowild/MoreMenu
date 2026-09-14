import Foundation
import Testing

struct MoreMenuTests {
    private func withPreferences(_ body: (MenuPreferences, UserDefaults) throws -> Void) throws {
        let suite = "MoreMenuTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(MenuPreferences(defaults: defaults), defaults)
    }

    @Test func defaultsEnableOnlyCoreTypes() throws {
        try withPreferences { preferences, _ in
            #expect(preferences.isMenuEnabled)
            #expect(preferences.enabledKinds == [.plainText, .markdown, .richText])
        }
    }

    @Test func selectionsPersistAcrossReadersAndRespectMasterSwitch() throws {
        try withPreferences { preferences, defaults in
            preferences.setEnabled(true, for: .typescript)
            preferences.setEnabled(false, for: .markdown)
            let reader = MenuPreferences(defaults: defaults)
            #expect(reader.enabledKinds == [.plainText, .richText, .typescript])
            preferences.isMenuEnabled = false
            #expect(reader.activeKinds.isEmpty)
            #expect(reader.enabledKinds.contains(.typescript))
        }
    }

    @Test func emptySelectionStaysEmptyAndUnknownTypesAreIgnored() throws {
        try withPreferences { preferences, defaults in
            defaults.set([String](), forKey: MenuPreferences.enabledDocumentKeysKey)
            #expect(preferences.enabledKinds.isEmpty)
            defaults.set(["unknown", "vue", "vue"], forKey: MenuPreferences.enabledDocumentKeysKey)
            #expect(preferences.enabledKinds == [.vue])
        }
    }

    @Test func migrationPreservesChoicesWithoutOverwritingNewSettings() throws {
        try withPreferences { preferences, _ in
            let data = Data(#"{"finderMenuEnabled":false,"enabledDocumentKeys":["vue","plainText","unknown"]}"#.utf8)
            try preferences.importLegacySettings(data)
            #expect(!preferences.isMenuEnabled)
            #expect(preferences.enabledKinds == [.plainText, .vue])
            preferences.isMenuEnabled = true
            preferences.setEnabled(true, for: .json)
            try preferences.importLegacySettings(data)
            #expect(preferences.isMenuEnabled)
            #expect(preferences.enabledKinds == [.plainText, .json, .vue])
        }
    }

    @Test func invalidMigrationDoesNotPartiallyChangePreferences() throws {
        try withPreferences { preferences, _ in
            let data = Data(#"{"finderMenuEnabled":false,"enabledDocumentKeys":123}"#.utf8)
            #expect(throws: DecodingError.self) { try preferences.importLegacySettings(data) }
            #expect(preferences.isMenuEnabled)
            #expect(preferences.enabledKinds == [.plainText, .markdown, .richText])
        }
    }

    @Test func emptyAndRepeatedImportsAreNoOps() throws {
        try withPreferences { preferences, _ in
            let emptyChanged = try preferences.importLegacySettings(Data("{}".utf8))
            let data = Data(#"{"finderMenuEnabled":false}"#.utf8)
            let firstChanged = try preferences.importLegacySettings(data)
            let repeatedChanged = try preferences.importLegacySettings(data)
            #expect(!emptyChanged)
            #expect(firstChanged)
            #expect(!repeatedChanged)
        }
    }

    @Test func catalogHasUniquePersistentKeysAndExtensions() {
        #expect(DocumentKind.allCases.count == 19)
        #expect(Set(DocumentKind.allCases.map(\.rawValue)).count == 19)
        #expect(Set(DocumentKind.allCases.map(\.fileExtension)).count == 19)
        #expect(DocumentKind.yaml.fileExtension == "yml")
        #expect(DocumentKind.plainText.menuTitle == "New Textfile")
    }
}
