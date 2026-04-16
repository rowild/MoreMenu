//
//  FinderSync.swift
//  MoreMenuExtension
//
//  Created by Robert Wildling on 2026-04-07.
//
//  Architecture note:
//  A Finder Sync Extension is sandboxed.  The `com.apple.security.temporary-exception.files.home-relative-path.read-write`
//  entitlement (set to ["/"]) grants the extension read-write access to the user's entire home
//  directory tree without requiring any Apple Events, security-scoped bookmarks, or IPC with
//  the host app.  File creation is therefore a direct Data.write(to:) call — no Finder
//  scripting, no bookmark resolution, no startAccessingSecurityScopedResource() needed.
//
//  Reference implementation that confirmed this approach:
//  https://github.com/suolapeikko/FinderUtilities
//

import Cocoa
import FinderSync
import OSLog

class FinderSync: FIFinderSync {

    // MARK: - Document types

    private enum DocumentKind: String, CaseIterable {
        case plainText
        case markdown
        case richText

        var menuTitle: String {
            switch self {
            case .plainText:
                return "New Textfile"
            case .markdown:
                return "New Markdown File"
            case .richText:
                return "New Rich Text File"
            }
        }

        var symbolName: String {
            switch self {
            case .plainText:
                return "doc.plaintext"
            case .markdown:
                return "doc.text"
            case .richText:
                return "doc.richtext"
            }
        }

        var baseName: String { "untitled" }

        var fileExtension: String {
            switch self {
            case .plainText:
                return "txt"
            case .markdown:
                return "md"
            case .richText:
                return "rtf"
            }
        }

        var initialContents: Data {
            switch self {
            case .plainText, .markdown:
                return Data()
            case .richText:
                // Minimal valid RTF so TextEdit and other rich-text apps open it
                // as a rich-text document instead of a zero-byte plain file.
                let rtf = #"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\fs24 }"#
                return Data(rtf.utf8)
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "GMX.MoreMenu.MoreMenuExtension", category: "FinderSync")

    /// Tracks which FIMenuKind built the current menu so the action handler can
    /// resolve the correct target directory.
    private var currentMenuKind: FIMenuKind = .contextualMenuForContainer

    // MARK: - Init

    override init() {
        super.init()
        // Monitor the entire local filesystem so Finder calls menu(for:) for
        // every folder and the Desktop.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - FIFinderSync overrides

    /// Returns the custom context menu injected into Finder.
    ///
    /// Handles:
    /// - `.contextualMenuForContainer` — right-click on empty space
    /// - `.contextualMenuForItems`     — right-click on a selected file or folder
    ///
    /// `.contextualMenuForSidebar` is excluded: no reliable target directory.
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForItems else {
            return NSMenu(title: "")
        }

        let menu = NSMenu(title: "")

        guard targetDirectory(for: menuKind) != nil else {
            return menu
        }

        currentMenuKind = menuKind

        for kind in DocumentKind.allCases {
            let menuItem = NSMenuItem(
                title: kind.menuTitle,
                action: #selector(newDocumentAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = kind.rawValue
            menuItem.image = symbolImage(named: kind.symbolName)
            menu.addItem(menuItem)
        }

        return menu
    }

    // MARK: - Menu action

    @objc func newDocumentAction(_ sender: NSMenuItem) {
        guard let targetURL = targetDirectory(for: currentMenuKind) else {
            logger.error("No resolvable target directory for menu action")
            return
        }

        guard
            let rawValue = sender.representedObject as? String,
            let kind = DocumentKind(rawValue: rawValue)
        else {
            logger.error("Menu action missing document kind")
            return
        }

        logger.log("Creating \(kind.fileExtension, privacy: .public) file in: \(targetURL.path, privacy: .public)")

        do {
            let createdURL = try createFile(in: targetURL, as: kind)
            logger.log("Successfully created: \(createdURL.path, privacy: .public)")
            presentCreatedFile(createdURL)
        } catch {
            logger.error("Failed to create file: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    // MARK: - Target directory resolution

    private func targetDirectory(for menuKind: FIMenuKind) -> URL? {
        if let targetedURL = FIFinderSyncController.default().targetedURL() {
            return normalizedDirectoryURL(from: targetedURL)
        }
        guard menuKind == .contextualMenuForContainer else { return nil }
        return currentInsertionLocation()
    }

    /// Returns `url` if it is a directory, otherwise its parent directory.
    /// Ensures right-clicking a file creates the new file alongside it.
    private func normalizedDirectoryURL(from url: URL) -> URL {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == true ? url : url.deletingLastPathComponent()
    }

    /// Asks Finder (via Apple Events) for the path of the currently-viewed folder.
    /// Falls back to the Desktop if no Finder window is open.
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
        guard let scriptObject = NSAppleScript(source: script) else { return nil }
        let result = scriptObject.executeAndReturnError(&error)
        guard error == nil, let path = result.stringValue else {
            logger.error("AppleScript error getting insertion location: \(String(describing: error), privacy: .public)")
            return nil
        }
        return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - File creation

    /// Creates a new document in `directoryURL` with content suited to its file type.
    ///
    /// The `com.apple.security.temporary-exception.files.home-relative-path.read-write`
    /// entitlement (set to ["/"]) grants the extension write access to the user's home
    /// directory tree, so no Apple Events or security-scoped bookmarks are needed.
    ///
    /// Naming sequence: untitled.ext → untitled_0001.ext → untitled_0002.ext …
    private func createFile(in directoryURL: URL, as kind: DocumentKind) throws -> URL {
        var candidate = directoryURL.appendingPathComponent("\(kind.baseName).\(kind.fileExtension)")
        var counter = 0

        while FileManager.default.fileExists(atPath: candidate.path) {
            counter += 1
            let padded = String(format: "%04d", counter)
            candidate = directoryURL.appendingPathComponent("\(kind.baseName)_\(padded).\(kind.fileExtension)")
        }

        try kind.initialContents.write(to: candidate, options: .atomic)
        return candidate
    }

    // MARK: - File presentation

    private func presentCreatedFile(_ fileURL: URL) {
        if !NSWorkspace.shared.open(fileURL) {
            logger.error("Could not open \(fileURL.path, privacy: .public); selecting in Finder instead")
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private func symbolImage(named symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }
}
