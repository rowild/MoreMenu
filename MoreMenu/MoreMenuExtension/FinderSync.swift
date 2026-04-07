//
//  FinderSync.swift
//  MoreMenuExtension
//
//  Created by Robert Wildling on 2026-04-07.
//

import Cocoa
import FinderSync
import OSLog

class FinderSync: FIFinderSync {
    private static let appGroupIdentifier = "group.GMX.MoreMenu.shared"
    private static let menuItemTitle = "New Textfile"
    private static let bookmarkStoreKey = "AuthorizedFolderBookmarks"
    private let logger = Logger(subsystem: "GMX.MoreMenu.MoreMenuExtension", category: "FinderSync")

    override init() {
        super.init()

        // Ask Finder to surface the extension for local folders.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        guard menuKind == .contextualMenuForContainer else {
            return NSMenu(title: "")
        }

        let menu = NSMenu(title: "")

        guard targetDirectory(for: menuKind) != nil else {
            return menu
        }

        let newItem = NSMenuItem(
            title: Self.menuItemTitle,
            action: #selector(newTextFileAction(_:)),
            keyEquivalent: ""
        )
        if let icon = NSImage(named: "MenuFileIcon") {
            icon.isTemplate = false
            newItem.image = icon
        }
        newItem.target = self
        menu.addItem(newItem)

        return menu
    }

    @objc func newTextFileAction(_ sender: AnyObject) {
        guard let targetURL = targetDirectory(for: .contextualMenuForContainer) else {
            logger.error("Menu action invoked without a resolvable target directory")
            return
        }

        logger.log("Creating text file in target directory: \(targetURL.path, privacy: .public)")

        do {
            let createdURL = try createFileWithAccessIfNeeded(in: targetURL)
            logger.log("Successfully created a new text file at \(createdURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to create a new text file: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    private func targetDirectory(for menuKind: FIMenuKind) -> URL? {
        if let targetedURL = FIFinderSyncController.default().targetedURL() {
            return normalizedDirectoryURL(from: targetedURL)
        }

        guard menuKind == .contextualMenuForContainer else {
            return nil
        }

        return currentInsertionLocation()
    }

    private func normalizedDirectoryURL(from url: URL) -> URL {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if resourceValues?.isDirectory == true {
            return url
        }

        return url.deletingLastPathComponent()
    }

    private func currentInsertionLocation() -> URL? {
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                return POSIX path of (insertion location as alias)
            else
                return POSIX path of (desktop as alias)
            end if
        end tell
        """

        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else {
            return nil
        }

        let result = scriptObject.executeAndReturnError(&error)
        guard error == nil, let path = result.stringValue else {
            logger.error("Failed to resolve Finder insertion location: \(String(describing: error), privacy: .public)")
            return nil
        }

        return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func createFileWithAccessIfNeeded(in directoryURL: URL) throws -> URL {
        guard let bookmarkURL = authorizedBookmarkURL(for: directoryURL) else {
            throw FinderFileError.accessNotGranted(directoryURL.path)
        }

        return try createFile(in: directoryURL, authorizedBy: bookmarkURL)
    }

    private func createFile(in directoryURL: URL, authorizedBy scopeURL: URL?) throws -> URL {
        let resourceValues = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues.isDirectory == true else {
            throw FinderFileError.notADirectory(directoryURL.path)
        }

        let accessedScope = scopeURL?.startAccessingSecurityScopedResource() ?? false
        if let scopeURL {
            logger.log(
                "Resolved bookmark scope \(scopeURL.path, privacy: .public); startAccessingSecurityScopedResource returned \(accessedScope)"
            )
        }

        guard accessedScope || scopeURL == nil else {
            throw FinderFileError.accessNotGranted(directoryURL.path)
        }

        defer {
            if accessedScope {
                scopeURL?.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let fileURL = nextAvailableFileURL(in: directoryURL, using: fileManager)

        do {
            try Data().write(to: fileURL, options: .withoutOverwriting)
        } catch {
            throw FinderFileError.creationFailed(fileURL.path, String(describing: error))
        }

        presentCreatedFile(fileURL)
        return fileURL
    }

    private func nextAvailableFileURL(in directoryURL: URL, using fileManager: FileManager) -> URL {
        let originalURL = directoryURL.appendingPathComponent("untitled.txt")
        if !fileManager.fileExists(atPath: originalURL.path) {
            return originalURL
        }

        var counter = 1
        while true {
            let candidateName = String(format: "untitled_%04d.txt", counter)
            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    private func authorizedBookmarkURL(for targetURL: URL) -> URL? {
        sharedDefaults.synchronize()
        let bookmarks = sharedDefaults.array(forKey: Self.bookmarkStoreKey) as? [Data] ?? []
        let standardizedTarget = targetURL.standardizedFileURL.path

        logger.log("Loaded \(bookmarks.count) bookmark entries for target \(standardizedTarget, privacy: .public)")

        var bestMatch: URL?
        var bestMatchLength = -1

        for (index, bookmarkData) in bookmarks.enumerated() {
            var isStale = false
            let resolvedURL: URL
            do {
                resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            } catch {
                logger.error("Bookmark \(index) failed to resolve: \(String(describing: error), privacy: .public)")
                continue
            }

            let resolvedPath = resolvedURL.standardizedFileURL.path
            let isSameFolder = standardizedTarget == resolvedPath
            let isDescendant = standardizedTarget.hasPrefix(resolvedPath + "/")

            logger.log(
                "Bookmark \(index) resolved to \(resolvedPath, privacy: .public); stale=\(isStale) sameFolder=\(isSameFolder) descendant=\(isDescendant)"
            )
            guard isSameFolder || isDescendant else {
                continue
            }

            if resolvedPath.count > bestMatchLength {
                bestMatch = resolvedURL
                bestMatchLength = resolvedPath.count
            }
        }

        if let bestMatch {
            logger.log("Using bookmark rooted at \(bestMatch.path, privacy: .public) for target \(standardizedTarget, privacy: .public)")
        } else {
            logger.error("No bookmark matched target \(standardizedTarget, privacy: .public)")
        }

        return bestMatch
    }

    private func presentCreatedFile(_ fileURL: URL) {
        if !NSWorkspace.shared.open(fileURL) {
            logger.error("Failed to open created file at \(fileURL.path, privacy: .public); falling back to Finder selection")
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private var sharedDefaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
            fatalError("Unable to open shared defaults for app group \(Self.appGroupIdentifier)")
        }
        return defaults
    }
}

private enum FinderFileError: Error {
    case notADirectory(String)
    case creationFailed(String, String)
    case accessNotGranted(String)
}
