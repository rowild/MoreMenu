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

private let sharedDefaultsSuiteName = "group.GMX.MoreMenu"
private let finderMenuEnabledKey = "finderMenuEnabled"
private let enabledDocumentKeysKey = "enabledDocumentKeys"

class FinderSync: FIFinderSync {

    // MARK: - Document types

    private enum DocumentKind: String, CaseIterable {
        case plainText
        case markdown
        case richText
        case json
        case yaml
        case toml
        case xml
        case csv
        case log
        case html
        case css
        case scss
        case javascript
        case jsx
        case typescript
        case tsx
        case vue
        case shellScript
        case python

        var menuTitle: String {
            switch self {
            case .plainText:
                return "New Textfile"
            case .markdown:
                return "New Markdown File"
            case .richText:
                return "New Rich Text File"
            case .json:
                return "New JSON File"
            case .yaml:
                return "New YAML File"
            case .toml:
                return "New TOML File"
            case .xml:
                return "New XML File"
            case .csv:
                return "New CSV File"
            case .log:
                return "New Log File"
            case .html:
                return "New HTML File"
            case .css:
                return "New CSS File"
            case .scss:
                return "New SCSS File"
            case .javascript:
                return "New JavaScript File"
            case .jsx:
                return "New JSX File"
            case .typescript:
                return "New TypeScript File"
            case .tsx:
                return "New TSX File"
            case .vue:
                return "New Vue Component"
            case .shellScript:
                return "New Shell Script"
            case .python:
                return "New Python File"
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
            default:
                return "doc.text"
            }
        }

        var defaultEnabled: Bool {
            switch self {
            case .plainText, .markdown, .richText:
                return true
            default:
                return false
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
            case .json:
                return "json"
            case .yaml:
                return "yml"
            case .toml:
                return "toml"
            case .xml:
                return "xml"
            case .csv:
                return "csv"
            case .log:
                return "log"
            case .html:
                return "html"
            case .css:
                return "css"
            case .scss:
                return "scss"
            case .javascript:
                return "js"
            case .jsx:
                return "jsx"
            case .typescript:
                return "ts"
            case .tsx:
                return "tsx"
            case .vue:
                return "vue"
            case .shellScript:
                return "sh"
            case .python:
                return "py"
            }
        }

        var initialContents: Data {
            switch self {
            case .plainText,
                    .markdown,
                    .json,
                    .yaml,
                    .toml,
                    .xml,
                    .csv,
                    .log,
                    .html,
                    .css,
                    .scss,
                    .javascript,
                    .jsx,
                    .typescript,
                    .tsx,
                    .vue,
                    .shellScript,
                    .python:
                return Data()
            case .richText:
                // Minimal valid RTF so TextEdit and other rich-text apps open it
                // as a rich-text document instead of a zero-byte plain file.
                let rtf = #"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\fs24 }"#
                return Data(rtf.utf8)
            }
        }

        static func enabledKinds(using defaults: UserDefaults) -> [DocumentKind] {
            let isMenuEnabled = defaults.object(forKey: finderMenuEnabledKey) == nil
                ? true
                : defaults.bool(forKey: finderMenuEnabledKey)

            guard isMenuEnabled else { return [] }

            if let storedKeys = defaults.stringArray(forKey: enabledDocumentKeysKey) {
                let enabledKeys = Set(storedKeys)
                return allCases.filter { enabledKeys.contains($0.rawValue) }
            }

            return allCases.filter(\.defaultEnabled)
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
        let enabledKinds = activeDocumentKinds()

        guard targetDirectory(for: menuKind) != nil, !enabledKinds.isEmpty else {
            return menu
        }

        currentMenuKind = menuKind

        for kind in enabledKinds {
            let menuItem = NSMenuItem(
                title: kind.menuTitle,
                action: #selector(newDocumentAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.image = symbolImage(named: kind.symbolName)
            menu.addItem(menuItem)
        }

        return menu
    }

    // MARK: - Menu action

    @objc func newDocumentAction(_ sender: NSMenuItem) {
        guard let kind = kind(forMenuTitle: sender.title) else {
            logger.error("Could not resolve document kind for menu title: \(sender.title, privacy: .public)")
            return
        }
        createDocument(kind)
    }

    private func createDocument(_ kind: DocumentKind) {
        guard let targetURL = targetDirectory(for: currentMenuKind) else {
            logger.error("No resolvable target directory for menu action")
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

    private func activeDocumentKinds() -> [DocumentKind] {
        let defaults = UserDefaults(suiteName: sharedDefaultsSuiteName) ?? .standard
        return DocumentKind.enabledKinds(using: defaults)
    }

    private func kind(forMenuTitle title: String) -> DocumentKind? {
        activeDocumentKinds().first { $0.menuTitle == title }
            ?? DocumentKind.allCases.first { $0.menuTitle == title }
    }

    private func symbolImage(named symbolName: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard
            let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else {
            return nil
        }

        let imageRect = NSRect(origin: .zero, size: baseImage.size)
        let whiteImage = NSImage(size: baseImage.size)
        whiteImage.lockFocus()
        baseImage.draw(in: imageRect)
        NSColor.white.set()
        imageRect.fill(using: .sourceAtop)
        whiteImage.unlockFocus()
        whiteImage.isTemplate = false
        return whiteImage
    }
}
