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
private let authorizedFolderRecordsKey = "authorizedFolderRecords"
private let sharedAuthorizedFolderEntriesKey = "sharedAuthorizedFolderEntries"

private enum SettingsPane: String, CaseIterable, Identifiable {
    case finder
    case fileTypes
    case authorizedFolders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finder:
            return "Finder"
        case .fileTypes:
            return "File Types"
        case .authorizedFolders:
            return "Authorized Folders"
        }
    }

    var symbolName: String {
        switch self {
        case .finder:
            return "finder"
        case .fileTypes:
            return "doc.text"
        case .authorizedFolders:
            return "externaldrive.badge.plus"
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

private struct AuthorizedFolderRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var path: String
    var persistentBookmark: Data
}

private struct SharedAuthorizedFolderEntry: Codable, Hashable {
    var path: String
    var bookmarkData: Data
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

@MainActor
private final class AuthorizedFoldersStore: ObservableObject {
    @Published private(set) var folders: [AuthorizedFolderRecord] = []
    @Published var statusMessage = "Folders in your Home folder work automatically. Authorize external drives or other locations once here."

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = UserDefaults(suiteName: sharedDefaultsSuiteName) ?? .standard) {
        self.defaults = defaults
        reload()
    }

    func addFolders() {
        let panel = NSOpenPanel()
        panel.title = "Authorize Folders"
        panel.message = "Choose one or more folders on external drives or outside your Home folder."
        panel.prompt = "Authorize"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")

        guard panel.runModal() == .OK else {
            statusMessage = "Folder authorization was not changed."
            return
        }

        var records = loadRecords()
        var addedPaths: [String] = []
        var rejectedPaths: [(path: String, reason: String)] = []

        for selectedURL in panel.urls {
            let standardizedURL = selectedURL.standardizedFileURL

            // TODO(user): decide the rejection policy for selected paths.
            // Returning a non-nil String rejects the folder with that reason;
            // returning nil accepts it.
            //
            // Known-bad buckets to consider:
            //  - inside or equal to the real user home → already covered by
            //    the extension's home-relative-path entitlement, record is
            //    redundant.
            //  - path is "/", "/Users", "/Volumes" → sandbox cannot actually
            //    grant access to these roots; bookmark minting will fail.
            //  - anywhere else → almost certainly a valid external/non-home
            //    target we want to accept.
            if let reason = rejectionReason(for: standardizedURL) {
                rejectedPaths.append((standardizedURL.path, reason))
                continue
            }

            let started = standardizedURL.startAccessingSecurityScopedResource()
            defer {
                if started {
                    standardizedURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let bookmark = try standardizedURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                let path = standardizedURL.path
                records.removeAll { $0.path == path }
                records.append(
                    AuthorizedFolderRecord(
                        id: UUID(),
                        path: path,
                        persistentBookmark: bookmark
                    )
                )
                addedPaths.append(path)
            } catch {
                statusMessage = "Failed to store folder access for \(standardizedURL.path): \(error.localizedDescription)"
            }
        }

        persist(records)
        refreshAccessCache()

        if !addedPaths.isEmpty && rejectedPaths.isEmpty {
            statusMessage = "Authorized \(addedPaths.count) folder(s). External locations should now work after Finder refreshes its context menu."
        } else if !rejectedPaths.isEmpty {
            let skipped = rejectedPaths
                .map { "Skipped \($0.path): \($0.reason)" }
                .joined(separator: "\n")
            if addedPaths.isEmpty {
                statusMessage = skipped
            } else {
                statusMessage = "Authorized \(addedPaths.count) folder(s).\n\(skipped)"
            }
        }
    }

    private func rejectionReason(for url: URL) -> String? {
        let path = url.standardizedFileURL.path
        let forbidden: Set<String> = ["/", "/Users", "/Volumes", "/System", "/Library", "/private"]
        if forbidden.contains(path) {
            return "system root folders cannot be authorized"
        }
        let realHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == realHome || path.hasPrefix(realHome + "/") {
            return "already covered by MoreMenu's built-in Home-folder access"
        }
        return nil
    }

    func remove(_ folder: AuthorizedFolderRecord) {
        let remaining = loadRecords().filter { $0.id != folder.id }
        persist(remaining)
        refreshAccessCache()
        statusMessage = "Removed authorization for \(folder.path)."
    }

    func refreshAccessCache() {
        var refreshedRecords: [AuthorizedFolderRecord] = []
        var sharedEntries: [SharedAuthorizedFolderEntry] = []
        var staleCount = 0

        for record in loadRecords() {
            if rejectionReason(for: URL(fileURLWithPath: record.path)) != nil {
                continue
            }
            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: record.persistentBookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                let standardizedURL = resolvedURL.standardizedFileURL
                let started = standardizedURL.startAccessingSecurityScopedResource()
                defer {
                    if started {
                        standardizedURL.stopAccessingSecurityScopedResource()
                    }
                }

                guard started else {
                    statusMessage = "Could not refresh folder access for \(record.path). Re-authorize it if external-folder creation stops working."
                    continue
                }

                var refreshedRecord = record
                if isStale || record.path != standardizedURL.path {
                    staleCount += 1
                    refreshedRecord.path = standardizedURL.path
                    refreshedRecord.persistentBookmark = try standardizedURL.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }

                // Minimal bookmark for cross-process sharing via App Group.
                // Security-scoped bookmark data is not portable between the host
                // and its Finder Sync extension (Apple dev-forum 66259); the
                // extension resolves this minimal bookmark with .withoutUI and
                // then mints its own .withSecurityScope bookmark locally.
                let sharedBookmark = try standardizedURL.bookmarkData(
                    options: [.minimalBookmark],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                refreshedRecords.append(refreshedRecord)
                sharedEntries.append(
                    SharedAuthorizedFolderEntry(
                        path: standardizedURL.path,
                        bookmarkData: sharedBookmark
                    )
                )
            } catch {
                statusMessage = "Failed to refresh external-folder access: \(error.localizedDescription)"
            }
        }

        persist(refreshedRecords)
        persistSharedEntries(sharedEntries)

        if folders.isEmpty && refreshedRecords.isEmpty {
            statusMessage = "Folders in your Home folder work automatically. Authorize external drives or other locations once here."
        } else if !refreshedRecords.isEmpty {
            statusMessage = staleCount == 0
                ? "Authorized folders are ready. External locations matching these folders should work."
                : "Authorized folders were refreshed. \(staleCount) stale bookmark(s) were updated."
        }
    }

    func rowNote(for folder: AuthorizedFolderRecord) -> String {
        isInsideHomeDirectory(folder.path)
            ? "Already covered by MoreMenu's built-in Home-folder access."
            : "Used for folders on external drives and other locations outside your Home folder."
    }

    private func reload() {
        folders = loadRecords().sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        refreshAccessCache()
        folders = loadRecords().sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func persist(_ records: [AuthorizedFolderRecord]) {
        folders = records.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        if let data = try? encoder.encode(folders) {
            defaults.set(data, forKey: authorizedFolderRecordsKey)
        } else {
            defaults.removeObject(forKey: authorizedFolderRecordsKey)
        }
    }

    private func persistSharedEntries(_ entries: [SharedAuthorizedFolderEntry]) {
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: sharedAuthorizedFolderEntriesKey)
        } else {
            defaults.removeObject(forKey: sharedAuthorizedFolderEntriesKey)
        }
    }

    private func loadRecords() -> [AuthorizedFolderRecord] {
        guard
            let data = defaults.data(forKey: authorizedFolderRecordsKey),
            let records = try? decoder.decode([AuthorizedFolderRecord].self, from: data)
        else {
            return []
        }

        return records
    }

    private func isInsideHomeDirectory(_ path: String) -> Bool {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return path == homePath || path.hasPrefix(homePath + "/")
    }
}

struct ContentView: View {
    @State private var selectedPane: SettingsPane = .finder
    @StateObject private var settings = SettingsStore()
    @StateObject private var authorizedFolders = AuthorizedFoldersStore()

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
                case .authorizedFolders:
                    AuthorizedFoldersPane(store: authorizedFolders)
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

private struct AuthorizedFoldersPane: View {
    @ObservedObject var store: AuthorizedFoldersStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                title: "Authorized Folders",
                subtitle: "Folders in your Home folder already work. Use this page for external drives and other locations outside your Home folder."
            )

            HStack(spacing: 12) {
                Button("Add Folder...") {
                    store.addFolders()
                }

                Button("Refresh Access") {
                    store.refreshAccessCache()
                }
            }

            Text(store.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.folders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No external folders authorized")
                        .font(.headline)
                    Text("Add a parent folder once. MoreMenu will then work inside that folder and its subfolders on external drives and other non-Home locations.")
                        .foregroundStyle(.secondary)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            } else {
                List {
                    ForEach(store.folders) { folder in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(folder.path)
                                    .textSelection(.enabled)
                                Text(store.rowNote(for: folder))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 16)

                            Button("Remove") {
                                store.remove(folder)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.inset)
            }

            Spacer(minLength: 0)
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
