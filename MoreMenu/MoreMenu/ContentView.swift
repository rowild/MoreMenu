//
//  ContentView.swift
//  MoreMenu
//
//  Created by Robert Wildling on 2026-04-07.
//
//  The host app's sole purpose is the permission setup flow.  macOS sandboxes the
//  Finder extension in a separate process, so the extension cannot ask for folder
//  access itself.  Instead:
//    1. This app presents an NSOpenPanel so the user explicitly picks a folder.
//    2. It stores a security-scoped bookmark for that folder in the shared App Group.
//    3. The extension reads that bookmark, resolves it with .withSecurityScope, and
//       calls startAccessingSecurityScopedResource() before writing files.
//

import AppKit
import SwiftUI

// MARK: - Shared constants

/// Keys and identifiers shared between the host app and the extension.
/// Both targets access the same App Group container, so these values must be
/// kept in sync between ContentView.swift and FinderSync.swift.
private enum SharedAccessStore {
    static let appGroupIdentifier = "group.GMX.MoreMenu.shared"
    static let bookmarkStoreKey   = "AuthorizedFolderBookmarks"

    /// Increment this when the on-disk bookmark format changes and a migration is
    /// needed.  The migration runs once and then records this version so it does not
    /// re-run on every subsequent launch.
    ///
    /// Version history:
    ///   1 — converted bookmarks from .withSecurityScope (wrong, app-scoped only) to options: []
    ///   2 — converted bookmarks from options: [] (no scope) to .withSecurityScope
    ///       (requires com.apple.security.files.bookmarks.app-scope on the host app)
    static let currentMigrationVersion = 2
    static let migrationVersionKey     = "BookmarkMigrationVersion"
}

// MARK: - Access model

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

    // MARK: - Public interface

    func grantFolderAccess() {
        let panel = NSOpenPanel()
        panel.title                = "Grant Folder Access"
        panel.message              = "Choose a folder that MoreMenu may write into. To cover Desktop, Documents, and other folders in your home directory, choose your home folder."
        panel.prompt               = "Grant Access"
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        // FileManager.homeDirectoryForCurrentUser returns the sandbox container in a
        // sandboxed app, not the real home directory.  Construct the real path directly.
        panel.directoryURL = URL(fileURLWithPath: "/Users/\(NSUserName())")

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            statusMessage = "Folder access was not changed."
            return
        }

        do {
            // The user selected this URL via NSOpenPanel, so we have implicit
            // permission.  We do NOT pass .withSecurityScope here — that flag
            // creates an app-scoped bookmark that cannot be transferred to the
            // extension process.  An implicit (options: []) bookmark can be
            // resolved by the extension with .withSecurityScope to activate the
            // security scope cross-process.
            let accessedScope = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if accessedScope { selectedURL.stopAccessingSecurityScopedResource() }
            }

            // .withSecurityScope creates a bookmark whose resolved URL supports
            // startAccessingSecurityScopedResource() in the sandboxed extension.
            // This requires com.apple.security.files.bookmarks.app-scope on this target.
            let bookmarkData = try selectedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            var entries = storedBookmarkEntries()
            // Remove any existing entry for the same folder so we don't accumulate
            // duplicates when the user grants access to the same folder twice.
            entries.removeAll { existing in
                guard let existingURL = resolveForComparison(existing) else { return true }
                return existingURL.standardizedFileURL == selectedURL.standardizedFileURL
            }
            entries.append(bookmarkData)
            saveBookmarkEntries(entries)

            reloadAuthorizedFolders()
            statusMessage = "Granted access to \(selectedURL.path). Finder may need a moment to pick up the new bookmark."
        } catch {
            statusMessage = "Failed to store folder access: \(error.localizedDescription)"
        }
    }

    func removeFolderAccess(_ folderURL: URL) {
        var entries = storedBookmarkEntries()
        entries.removeAll { existing in
            // options: [] is correct here — we only need the path for comparison,
            // not an activated security scope.  Using .withSecurityScope was a bug:
            // it would fail to match bookmarks stored with options: [], silently
            // leaving the entry in place.
            guard let existingURL = resolveForComparison(existing) else { return true }
            return existingURL.standardizedFileURL == folderURL.standardizedFileURL
        }
        saveBookmarkEntries(entries)
        reloadAuthorizedFolders()
        statusMessage = "Removed access for \(folderURL.path)."
    }

    func reloadAuthorizedFolders() {
        authorizedFolders = storedBookmarkEntries()
            .compactMap { resolveForDisplay($0) }
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
    }

    // MARK: - Migration

    /// Converts any bookmarks that were stored with the old `.withSecurityScope`
    /// flag to the implicit-scope format (`options: []`) expected by the extension.
    ///
    /// This migration only runs once: after completion it writes `currentMigrationVersion`
    /// to `migrationVersionKey` in shared defaults.  Subsequent launches skip it entirely.
    private func migrateStoredBookmarksIfNeeded() {
        guard let defaults = sharedDefaults else { return }

        let storedVersion = defaults.integer(forKey: SharedAccessStore.migrationVersionKey)
        guard storedVersion < SharedAccessStore.currentMigrationVersion else { return }

        let entries = storedBookmarkEntries()
        guard !entries.isEmpty else {
            // Nothing to migrate; record the current version and exit.
            defaults.set(SharedAccessStore.currentMigrationVersion,
                         forKey: SharedAccessStore.migrationVersionKey)
            return
        }

        let migrated: [Data] = entries.compactMap { bookmarkData in
            // Resolve with options: [] to get the URL (works for both old-style
            // .withSecurityScope bookmarks and the current options: [] bookmarks).
            guard let resolvedURL = resolveForMigration(bookmarkData) else { return nil }

            // Re-create with .withSecurityScope so the extension can activate the
            // security scope via startAccessingSecurityScopedResource().
            // No prior startAccessingSecurityScopedResource() call is needed here
            // because the host app has user-selected.read-write, which grants
            // persistent access to previously-selected resources.
            if let upgraded = try? resolvedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                return upgraded
            }

            // If upgrading failed (e.g. the path no longer exists), keep the
            // existing entry rather than silently deleting access.
            return bookmarkData
        }

        if !migrated.isEmpty {
            saveBookmarkEntries(migrated)
        }

        defaults.set(SharedAccessStore.currentMigrationVersion,
                     forKey: SharedAccessStore.migrationVersionKey)
    }

    // MARK: - Bookmark helpers

    /// Loads the raw bookmark data array from shared defaults.
    private func storedBookmarkEntries() -> [Data] {
        sharedDefaults?.array(forKey: SharedAccessStore.bookmarkStoreKey) as? [Data] ?? []
    }

    /// Persists the bookmark data array to shared defaults.
    private func saveBookmarkEntries(_ entries: [Data]) {
        sharedDefaults?.set(entries, forKey: SharedAccessStore.bookmarkStoreKey)
    }

    /// Resolves bookmark data to a URL for **path comparison** only.
    ///
    /// options: [] is sufficient — we are not activating any security scope, just
    /// reading the path that the bookmark points to.
    private func resolveForComparison(_ bookmarkData: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// Resolves bookmark data to a URL for **display** in the authorized folders list.
    ///
    /// Tries options: [] first (the format used since the migration).  Falls back to
    /// .withSecurityScope to handle any pre-migration entries that may remain.
    private func resolveForDisplay(_ bookmarkData: Data) -> URL? {
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
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// Resolves bookmark data during migration, trying both options so it can handle
    /// both old-style (.withSecurityScope) and new-style (options: []) entries.
    private func resolveForMigration(_ bookmarkData: Data) -> URL? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
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

// MARK: - Views

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
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Extensions")!
                )
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
