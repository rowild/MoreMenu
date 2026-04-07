//
//  ContentView.swift
//  MoreMenu
//
//  Created by Robert Wildling on 2026-04-07.
//

import AppKit
import SwiftUI

private enum SharedAccessStore {
    static let appGroupIdentifier = "group.GMX.MoreMenu.shared"
    static let bookmarkStoreKey = "AuthorizedFolderBookmarks"
}

@MainActor
final class FolderAccessModel: ObservableObject {
    @Published var authorizedFolders: [URL] = []
    @Published var statusMessage = "Grant access to the folder tree where \"New Textfile\" should work."

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: SharedAccessStore.appGroupIdentifier)
    }

    init() {
        migrateStoredBookmarksIfNeeded()
        reloadAuthorizedFolders()
    }

    func grantFolderAccess() {
        let panel = NSOpenPanel()
        panel.title = "Grant Folder Access"
        panel.message = "Choose a folder that MoreMenu may write into. To cover Desktop, Documents, and other folders in your home directory, choose your home folder."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            statusMessage = "Folder access was not changed."
            return
        }

        do {
            let accessedScope = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if accessedScope {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }

            let bookmarkData = try selectedURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            var bookmarkEntries = sharedDefaults?.array(forKey: SharedAccessStore.bookmarkStoreKey) as? [Data] ?? []
            bookmarkEntries.removeAll { existingData in
                var isStale = false
                guard let existingURL = try? URL(
                    resolvingBookmarkData: existingData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) else {
                    return true
                }

                return existingURL.standardizedFileURL == selectedURL.standardizedFileURL
            }
            bookmarkEntries.append(bookmarkData)
            sharedDefaults?.set(bookmarkEntries, forKey: SharedAccessStore.bookmarkStoreKey)
            sharedDefaults?.synchronize()

            reloadAuthorizedFolders()
            statusMessage = "Granted access to \(selectedURL.path). Finder may need a moment to pick up the new bookmark."
        } catch {
            statusMessage = "Failed to store folder access: \(error.localizedDescription)"
        }
    }

    func removeFolderAccess(_ folderURL: URL) {
        var bookmarkEntries = sharedDefaults?.array(forKey: SharedAccessStore.bookmarkStoreKey) as? [Data] ?? []
        bookmarkEntries.removeAll { existingData in
            var isStale = false
            guard let existingURL = try? URL(
                resolvingBookmarkData: existingData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return true
            }

            return existingURL.standardizedFileURL == folderURL.standardizedFileURL
        }

        sharedDefaults?.set(bookmarkEntries, forKey: SharedAccessStore.bookmarkStoreKey)
        sharedDefaults?.synchronize()
        reloadAuthorizedFolders()
        statusMessage = "Removed access for \(folderURL.path)."
    }

    func reloadAuthorizedFolders() {
        sharedDefaults?.synchronize()
        let bookmarkEntries = sharedDefaults?.array(forKey: SharedAccessStore.bookmarkStoreKey) as? [Data] ?? []
        authorizedFolders = bookmarkEntries.compactMap(resolveStoredBookmark)
        .map(\.standardizedFileURL)
        .sorted { $0.path < $1.path }
    }

    private func migrateStoredBookmarksIfNeeded() {
        guard let sharedDefaults else {
            return
        }

        let bookmarkEntries = sharedDefaults.array(forKey: SharedAccessStore.bookmarkStoreKey) as? [Data] ?? []
        guard !bookmarkEntries.isEmpty else {
            return
        }

        let migratedBookmarks = bookmarkEntries.compactMap { bookmarkData -> Data? in
            guard let resolvedURL = resolveBookmarkForMigration(bookmarkData) else {
                return nil
            }

            let accessedScope = resolvedURL.startAccessingSecurityScopedResource()
            guard accessedScope else {
                return nil
            }

            defer {
                resolvedURL.stopAccessingSecurityScopedResource()
            }

            return try? resolvedURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        guard !migratedBookmarks.isEmpty else {
            return
        }

        sharedDefaults.set(migratedBookmarks, forKey: SharedAccessStore.bookmarkStoreKey)
        sharedDefaults.synchronize()
    }

    private func resolveStoredBookmark(_ bookmarkData: Data) -> URL? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }

        isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func resolveBookmarkForMigration(_ bookmarkData: Data) -> URL? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }

        isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}

struct ContentView: View {
    @StateObject private var accessModel = FolderAccessModel()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("MoreMenu Extension")
                .font(.title)
                .fontWeight(.bold)

            Text("Finder Sync can show the menu item, but macOS will not let the extension write into arbitrary folders unless the host app stores an explicit folder bookmark first.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Required setup")
                    .font(.headline)

                StepView(number: 1, text: "Keep the Finder extension enabled in System Settings.")
                StepView(number: 2, text: "Click \"Grant Folder Access…\" below.")
                StepView(number: 3, text: "Choose the exact folder or a parent folder. To cover Desktop and Documents, choose your home folder.")
                StepView(number: 4, text: "Return to Finder and try \"New Textfile\" again.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button("Grant Folder Access…") {
                    accessModel.grantFolderAccess()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Reload") {
                    accessModel.reloadAuthorizedFolders()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text(accessModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Authorized folders")
                    .font(.headline)

                if accessModel.authorizedFolders.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accessModel.authorizedFolders, id: \.path) { folderURL in
                        HStack {
                            Text(folderURL.path)
                                .font(.subheadline.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Remove") {
                                accessModel.removeFolderAccess(folderURL)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Extensions")!)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 520)
    }
}

struct StepView: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(.blue, in: Circle())
                .foregroundStyle(.white)

            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    ContentView()
}
