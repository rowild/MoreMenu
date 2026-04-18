//
//  FinderSync.swift
//  MoreMenuExtension
//
//  Created by Robert Wildling on 2026-04-07.
//
//  Access model (1.2.1+):
//  The extension's entitlements grant
//  `com.apple.security.temporary-exception.files.home-relative-path.read-write = /`,
//  which gives the sandbox the capability to write anywhere under the user's
//  home folder. Locations outside the home (notably `/Volumes/*` external
//  drives) are intentionally not supported: adding `absolute-path = /` works
//  for App-Store-signed apps like FiScript, but under the project's current
//  ad-hoc signing it cannot produce a stable TCC code requirement on macOS
//  Tahoe 26.4 and therefore cannot work silently across reinstalls. The
//  home-relative scope matches what version 1.1 shipped with and what the
//  user has consistently accepted ("prompted once after a new install").
//  See .claude/plans/0004_new_research_on_rightclick_permission.md for the
//  full signing/TCC research.
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
    private var currentMenuKind: FIMenuKind = .contextualMenuForContainer

    /// Real user home directory. Inside a sandboxed extension
    /// `FileManager.default.homeDirectoryForCurrentUser` returns the
    /// container's home (`…/Library/Containers/<bundle id>/Data`), which
    /// would make the home-scope check reject every real user folder.
    /// `getpwuid(getuid())` returns the actual login home regardless of
    /// sandbox, which is what the `home-relative-path` entitlement covers.
    private static let realUserHomePath: String = {
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            return String(cString: home)
        }
        return NSHomeDirectory()
    }()

    // MARK: - Init

    override init() {
        super.init()
        // Monitor the filesystem root. macOS's Finder Sync framework treats
        // "/" specially — it means "call me for any local folder Finder shows"
        // — and does NOT classify this as cross-app data access for App
        // Management. Registering a user-home path (e.g. "/Users/<user>")
        // instead causes macOS to treat the extension as observing every
        // other installed app's Container under ~/Library/Containers and
        // raises the Sonoma App Management consent prompt whenever another
        // app is launched. Invariant pinned by FinderSyncInvariantTests.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - FIFinderSync overrides

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForItems else {
            return NSMenu(title: "")
        }

        let menu = NSMenu(title: "")
        let enabledKinds = activeDocumentKinds()

        guard let target = targetDirectory(for: menuKind), !enabledKinds.isEmpty else {
            return menu
        }

        // Hide the menu in locations the sandbox entitlement can't reach:
        // filesystem root `/`, `/Volumes/*`, other users' homes, `/tmp`,
        // `/Applications`, etc. The user gets no false affordance for file
        // creation that would silently fail.
        guard isInsideUserHome(target) else {
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

        guard isInsideUserHome(targetURL) else {
            logger.error("Refusing to create file outside user home: \(targetURL.path, privacy: .public)")
            NSSound.beep()
            return
        }

        logger.log("Creating \(kind.fileExtension, privacy: .public) file in: \(targetURL.path, privacy: .public)")

        do {
            let createdURL = try createFile(in: targetURL, as: kind)
            logger.log("Successfully created: \(createdURL.path, privacy: .public)")
            presentCreatedFile(createdURL)
        } catch {
            logger.error("Failed to create file in \(targetURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
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

    private func normalizedDirectoryURL(from url: URL) -> URL {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == true ? url : url.deletingLastPathComponent()
    }

    private func isInsideUserHome(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = Self.realUserHomePath
        return path == home || path.hasPrefix(home + "/")
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
        guard let scriptObject = NSAppleScript(source: script) else { return nil }
        let result = scriptObject.executeAndReturnError(&error)
        guard error == nil, let path = result.stringValue else {
            logger.error("AppleScript error getting insertion location: \(String(describing: error), privacy: .public)")
            return nil
        }
        return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - File creation

    private func createFile(in directoryURL: URL, as kind: DocumentKind) throws -> URL {
        let standardizedDirectoryURL = directoryURL.standardizedFileURL

        var candidate = standardizedDirectoryURL.appendingPathComponent("\(kind.baseName).\(kind.fileExtension)")
        var counter = 0

        while FileManager.default.fileExists(atPath: candidate.path) {
            counter += 1
            let padded = String(format: "%04d", counter)
            candidate = standardizedDirectoryURL.appendingPathComponent("\(kind.baseName)_\(padded).\(kind.fileExtension)")
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
