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

private enum SettingsPane: String, CaseIterable, Identifiable {
    case finder
    case fileTypes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finder:
            return "Finder"
        case .fileTypes:
            return "File Types"
        }
    }

    var symbolName: String {
        switch self {
        case .finder:
            return "finder"
        case .fileTypes:
            return "doc.text"
        }
    }
}

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
    @State private var selectedPane: SettingsPane = .finder
    @StateObject private var settings = SettingsStore()

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(SettingsPane.allCases, id: \.self) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        SidebarRow(
                            pane: pane,
                            isSelected: selectedPane == pane
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 250)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch selectedPane {
                case .finder:
                    FinderSettingsPane(isMenuEnabled: settings.isMenuEnabled) {
                        settings.setMenuEnabled($0)
                    }
                case .fileTypes:
                    FileTypesPane(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(minWidth: 920, minHeight: 640)
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pane.symbolName)
                .frame(width: 18)
            Text(pane.title)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .foregroundStyle(.primary)
    }
}

private struct FinderSettingsPane: View {
    let isMenuEnabled: Bool
    let onSetMenuEnabled: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                title: "Finder",
                subtitle: "Control whether MoreMenu shows its commands in Finder. macOS still owns the actual Finder extension switch."
            )

            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    "Enable MoreMenu in Finder",
                    isOn: Binding(
                        get: { isMenuEnabled },
                        set: onSetMenuEnabled
                    )
                )
                .toggleStyle(.switch)

                Button("Open Finder Extension Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Extensions")!
                    )
                }

                Text("Use the macOS Finder Extensions settings if the menu does not appear at all. The switch above only hides or shows MoreMenu's own commands.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 0)
        }
    }
}

private struct FileTypesPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(
                    title: "File Types",
                    subtitle: "Choose which document types appear in Finder's first-level context menu."
                )

                ForEach(FileTypeCategory.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(category.rawValue)
                                .font(.headline)
                            Spacer()
                            Text("\(settings.enabledCount(in: category)) enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(documentPreferences.filter { $0.category == category }.enumerated()), id: \.element.id) { index, preference in
                                HStack(alignment: .top, spacing: 12) {
                                    Toggle("", isOn: settings.binding(for: preference))
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()

                                    Image(systemName: preference.symbolName)
                                        .frame(width: 18)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(preference.title) (.\(preference.fileExtension))")
                                        Text(preference.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)

                                if index < documentPreferences.filter({ $0.category == category }).count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(18)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

private struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
