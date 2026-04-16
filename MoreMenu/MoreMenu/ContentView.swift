//
//  ContentView.swift
//  MoreMenu
//
//  Created by Robert Wildling on 2026-04-07.
//

import AppKit
import SwiftUI

private let sharedDefaultsSuiteName = "group.GMX.MoreMenu"
private let finderMenuEnabledKey = "finderMenuEnabled"
private let enabledDocumentKeysKey = "enabledDocumentKeys"

private enum FileTypeCategory: String, CaseIterable {
    case core = "Core"
    case data = "Data"
    case web = "Web & App"
    case scripts = "Scripts"
}

private struct DocumentPreference: Identifiable, Hashable {
    let key: String
    let title: String
    let fileExtension: String
    let symbolName: String
    let category: FileTypeCategory
    let defaultEnabled: Bool
    let note: String

    var id: String { key }
}

private let documentPreferences: [DocumentPreference] = [
    DocumentPreference(
        key: "plainText",
        title: "Text",
        fileExtension: "txt",
        symbolName: "doc.plaintext",
        category: .core,
        defaultEnabled: true,
        note: "Plain text documents"
    ),
    DocumentPreference(
        key: "markdown",
        title: "Markdown",
        fileExtension: "md",
        symbolName: "doc.text",
        category: .core,
        defaultEnabled: true,
        note: "Notes, docs, and README files"
    ),
    DocumentPreference(
        key: "richText",
        title: "Rich Text",
        fileExtension: "rtf",
        symbolName: "doc.richtext",
        category: .core,
        defaultEnabled: true,
        note: "Formatted text for TextEdit and similar apps"
    ),
    DocumentPreference(
        key: "json",
        title: "JSON",
        fileExtension: "json",
        symbolName: "doc.text",
        category: .data,
        defaultEnabled: false,
        note: "Configuration, API payloads, package metadata"
    ),
    DocumentPreference(
        key: "yaml",
        title: "YAML",
        fileExtension: "yml",
        symbolName: "doc.text",
        category: .data,
        defaultEnabled: false,
        note: "CI files, manifests, infrastructure config"
    ),
    DocumentPreference(
        key: "toml",
        title: "TOML",
        fileExtension: "toml",
        symbolName: "doc.text",
        category: .data,
        defaultEnabled: false,
        note: "Tooling config such as Cargo or uv"
    ),
    DocumentPreference(
        key: "xml",
        title: "XML",
        fileExtension: "xml",
        symbolName: "doc.text",
        category: .data,
        defaultEnabled: false,
        note: "Structured data and feed files"
    ),
    DocumentPreference(
        key: "csv",
        title: "CSV",
        fileExtension: "csv",
        symbolName: "doc.text",
        category: .data,
        defaultEnabled: false,
        note: "Spreadsheet-style flat data"
    ),
    DocumentPreference(
        key: "log",
        title: "Log",
        fileExtension: "log",
        symbolName: "doc.text",
        category: .data,
        defaultEnabled: false,
        note: "Plain log output"
    ),
    DocumentPreference(
        key: "html",
        title: "HTML",
        fileExtension: "html",
        symbolName: "doc.text",
        category: .web,
        defaultEnabled: false,
        note: "Web pages and Angular templates"
    ),
    DocumentPreference(
        key: "css",
        title: "CSS",
        fileExtension: "css",
        symbolName: "doc.text",
        category: .web,
        defaultEnabled: false,
        note: "Stylesheets"
    ),
    DocumentPreference(
        key: "scss",
        title: "SCSS",
        fileExtension: "scss",
        symbolName: "doc.text",
        category: .web,
        defaultEnabled: false,
        note: "Sass styles used in Vue, React, and Angular projects"
    ),
    DocumentPreference(
        key: "javascript",
        title: "JavaScript",
        fileExtension: "js",
        symbolName: "doc.text",
        category: .web,
        defaultEnabled: false,
        note: "Runtime and tooling scripts"
    ),
    DocumentPreference(
        key: "jsx",
        title: "JSX",
        fileExtension: "jsx",
        symbolName: "doc.text",
        category: .web,
        defaultEnabled: false,
        note: "React components"
    ),
    DocumentPreference(
        key: "typescript",
        title: "TypeScript",
        fileExtension: "ts",
        symbolName: "doc.text",
        category: .web,
        defaultEnabled: false,
        note: "Typed app and framework code"
    ),
    DocumentPreference(
        key: "tsx",
        title: "TSX",
        fileExtension: "tsx",
        symbolName: "doc.text",
        category: .web,
        defaultEnabled: false,
        note: "Typed React components"
    ),
    DocumentPreference(
        key: "vue",
        title: "Vue Single-File Component",
        fileExtension: "vue",
        symbolName: "doc.text",
        category: .web,
        defaultEnabled: false,
        note: "Vue components"
    ),
    DocumentPreference(
        key: "shellScript",
        title: "Shell Script",
        fileExtension: "sh",
        symbolName: "doc.text",
        category: .scripts,
        defaultEnabled: false,
        note: "Shell commands and utility scripts"
    ),
    DocumentPreference(
        key: "python",
        title: "Python",
        fileExtension: "py",
        symbolName: "doc.text",
        category: .scripts,
        defaultEnabled: false,
        note: "Python scripts and tools"
    ),
]

private final class SettingsStore: ObservableObject {
    @Published var isMenuEnabled: Bool
    @Published private var enabledDocumentKeys: Set<String>

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: sharedDefaultsSuiteName) ?? .standard) {
        self.defaults = defaults

        if defaults.object(forKey: finderMenuEnabledKey) == nil {
            self.isMenuEnabled = true
        } else {
            self.isMenuEnabled = defaults.bool(forKey: finderMenuEnabledKey)
        }

        if let storedKeys = defaults.stringArray(forKey: enabledDocumentKeysKey) {
            self.enabledDocumentKeys = Set(storedKeys)
        } else {
            self.enabledDocumentKeys = Set(
                documentPreferences
                    .filter(\.defaultEnabled)
                    .map(\.key)
            )
        }
    }

    func binding(for preference: DocumentPreference) -> Binding<Bool> {
        Binding(
            get: { self.enabledDocumentKeys.contains(preference.key) },
            set: { isEnabled in
                if isEnabled {
                    self.enabledDocumentKeys.insert(preference.key)
                } else {
                    self.enabledDocumentKeys.remove(preference.key)
                }
                self.persistEnabledDocumentKeys()
            }
        )
    }

    func setMenuEnabled(_ isEnabled: Bool) {
        isMenuEnabled = isEnabled
        defaults.set(isEnabled, forKey: finderMenuEnabledKey)
    }

    func enabledCount(in category: FileTypeCategory) -> Int {
        documentPreferences.filter { $0.category == category && enabledDocumentKeys.contains($0.key) }.count
    }

    private func persistEnabledDocumentKeys() {
        let orderedKeys = documentPreferences
            .map(\.key)
            .filter { enabledDocumentKeys.contains($0) }
        defaults.set(orderedKeys, forKey: enabledDocumentKeysKey)
    }
}

struct ContentView: View {
    @StateObject private var settings = SettingsStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MoreMenu")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Choose which file types Finder should show in the context menu. Changes apply the next time you right-click.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section {
                    Toggle(
                        "Enable MoreMenu in Finder",
                        isOn: Binding(
                            get: { settings.isMenuEnabled },
                            set: { settings.setMenuEnabled($0) }
                        )
                    )

                    Button("Open Finder Extension Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Extensions")!
                        )
                    }
                    .buttonStyle(.link)

                    Text("macOS still controls whether the Finder extension itself is enabled. This switch only hides or shows MoreMenu's commands.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Finder")
                }

                ForEach(FileTypeCategory.allCases, id: \.self) { category in
                    Section {
                        ForEach(documentPreferences.filter { $0.category == category }) { preference in
                            Toggle(isOn: settings.binding(for: preference)) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: preference.symbolName)
                                        .frame(width: 18)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(preference.title) (.\(preference.fileExtension))")
                                        Text(preference.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(category.rawValue)
                            Spacer()
                            Text("\(settings.enabledCount(in: category)) enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("Built-in file types stay enabled by default so existing installs keep the same Finder menu. Extra web and app types are opt-in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 640)
    }
}

#Preview {
    ContentView()
}
