//
//  FinderSync.swift
//  MoreMenuExtension
//
//  Created by Robert Wildling on 2026-04-07.
//
//  Access model:
//  - Home-folder targets use the existing home-relative-path entitlement and
//    skip the bookmark dance entirely.
//  - Non-home targets (external drives, /Volumes, arbitrary locations) are
//    authorized by the user in the host app. The host serializes a
//    .minimalBookmark into the shared App Group defaults. On first use the
//    extension resolves that minimal bookmark (.withoutUI), mints a local
//    .withSecurityScope bookmark from the resolved URL, caches it in the
//    extension's private UserDefaults, and starts security-scoped access
//    from the cached bookmark on every subsequent invocation.
//
//  This two-step handoff is necessary because security-scoped bookmark data
//  is not portable across the host/extension boundary even inside the same
//  App Group — see Apple dev-forum 66259 ("Share security scoped bookmark in
//  app group?"), which documents the Code=259 "not in the correct format"
//  failure when trying to round-trip a .withSecurityScope bookmark through
//  shared defaults.
//

import Cocoa
import Darwin
import FinderSync
import OSLog

private let sharedDefaultsSuiteName = "group.GMX.MoreMenu"
private let finderMenuEnabledKey = "finderMenuEnabled"
private let enabledDocumentKeysKey = "enabledDocumentKeys"
private let sharedAuthorizedFolderEntriesKey = "sharedAuthorizedFolderEntries"

private struct SharedAuthorizedFolderEntry: Codable, Hashable {
    var path: String
    var bookmarkData: Data
}

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

    private struct FolderAccessScope {
        let stopAccessing: () -> Void

        static let none = FolderAccessScope(stopAccessing: {})
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "GMX.MoreMenu.MoreMenuExtension", category: "FinderSync")
    private var currentMenuKind: FIMenuKind = .contextualMenuForContainer
    private var observedDirectoryURL: URL?

    // MARK: - Init

    override init() {
        super.init()
        refreshMonitoredDirectories()
    }

    // MARK: - FIFinderSync overrides

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        refreshMonitoredDirectories()

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

    override func beginObservingDirectory(at url: URL) {
        observedDirectoryURL = url.standardizedFileURL
    }

    override func endObservingDirectory(at url: URL) {
        if observedDirectoryURL?.standardizedFileURL == url.standardizedFileURL {
            observedDirectoryURL = nil
        }
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
            NSLog("MoreMenuExtension: no target directory for %@", kind.fileExtension)
            return
        }

        logger.log("Creating \(kind.fileExtension, privacy: .public) file in: \(targetURL.path, privacy: .public)")
        NSLog("MoreMenuExtension: creating %@ in %@", kind.fileExtension, targetURL.path)

        do {
            let createdURL = try createFile(in: targetURL, as: kind)
            logger.log("Successfully created: \(createdURL.path, privacy: .public)")
            NSLog("MoreMenuExtension: created %@", createdURL.path)
            presentCreatedFile(createdURL)
        } catch {
            logger.error("Failed to create file: \(String(describing: error), privacy: .public)")
            NSLog("MoreMenuExtension: failed to create file in %@: %@", targetURL.path, String(describing: error))
            NSSound.beep()
        }
    }

    // MARK: - Target directory resolution

    private func targetDirectory(for menuKind: FIMenuKind) -> URL? {
        if let targetedURL = FIFinderSyncController.default().targetedURL() {
            return normalizedDirectoryURL(from: targetedURL)
        }
        if menuKind == .contextualMenuForContainer, let observedDirectoryURL {
            return normalizedDirectoryURL(from: observedDirectoryURL)
        }
        guard menuKind == .contextualMenuForContainer else { return nil }
        return currentInsertionLocation()
    }

    private func normalizedDirectoryURL(from url: URL) -> URL {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == true ? url : url.deletingLastPathComponent()
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
        let accessScope = try accessScope(for: standardizedDirectoryURL)
        defer { accessScope.stopAccessing() }

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

    // Two-step bookmark flow (Apple dev-forum 66259 workaround):
    //   1. Host writes a .minimalBookmark into the shared App Group defaults.
    //   2. Extension resolves that minimal bookmark with .withoutUI — this
    //      produces a URL that this extension process is authorized to use
    //      because both targets share the App Group and both carry the
    //      files.bookmarks.app-scope + files.user-selected.read-write
    //      entitlements.
    //   3. Extension mints its own .withSecurityScope bookmark from that URL
    //      and caches it in its local (non-shared) UserDefaults, keyed by
    //      the authorized-parent path. On subsequent invocations the
    //      extension reuses this local scoped bookmark directly — startAccessing
    //      is only valid on scoped bookmarks created in-process.
    private func accessScope(for directoryURL: URL) throws -> FolderAccessScope {
        if isInsideHomeDirectory(directoryURL) {
            return .none
        }

        guard let entry = bestAuthorizedFolderEntry(for: directoryURL) else {
            throw FinderFileError.accessNotGranted(directoryURL.path)
        }

        if let scope = startLocalScopedAccess(forAuthorizedPath: entry.path) {
            return scope
        }

        guard let scope = promoteSharedBookmark(entry) else {
            throw FinderFileError.accessNotGranted(directoryURL.path)
        }
        return scope
    }

    private func startLocalScopedAccess(forAuthorizedPath authorizedPath: String) -> FolderAccessScope? {
        guard let bookmarkData = loadLocalScopedBookmark(forAuthorizedPath: authorizedPath) else {
            return nil
        }

        do {
            var isStale = false
            let scopedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                logger.log("Local scoped bookmark stale for \(authorizedPath, privacy: .public); will re-promote from shared minimal bookmark.")
                removeLocalScopedBookmark(forAuthorizedPath: authorizedPath)
                return nil
            }

            guard scopedURL.startAccessingSecurityScopedResource() else {
                logger.error("startAccessingSecurityScopedResource() returned false for \(authorizedPath, privacy: .public); discarding cached bookmark.")
                removeLocalScopedBookmark(forAuthorizedPath: authorizedPath)
                return nil
            }

            logger.log("Started local security scope for \(authorizedPath, privacy: .public)")
            return FolderAccessScope {
                scopedURL.stopAccessingSecurityScopedResource()
            }
        } catch {
            logger.error("Local scoped bookmark resolution failed for \(authorizedPath, privacy: .public): \(String(describing: error), privacy: .public)")
            removeLocalScopedBookmark(forAuthorizedPath: authorizedPath)
            return nil
        }
    }

    private func promoteSharedBookmark(_ entry: SharedAuthorizedFolderEntry) -> FolderAccessScope? {
        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: entry.bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                logger.log("Shared minimal bookmark stale for \(entry.path, privacy: .public); host app should refresh it.")
            }

            let scopedBookmarkData: Data
            do {
                scopedBookmarkData = try resolvedURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                logger.error("Minting local scoped bookmark failed for \(entry.path, privacy: .public): \(String(describing: error), privacy: .public)")
                return nil
            }

            saveLocalScopedBookmark(scopedBookmarkData, forAuthorizedPath: entry.path)
            logger.log("Promoted shared minimal bookmark to local scoped bookmark for \(entry.path, privacy: .public)")

            return startLocalScopedAccess(forAuthorizedPath: entry.path)
        } catch {
            logger.error("Shared bookmark resolution failed for \(entry.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Local (extension-only) scoped bookmark cache

    private var localScopedBookmarkDefaults: UserDefaults { .standard }

    private func localScopedBookmarkKey(forAuthorizedPath authorizedPath: String) -> String {
        "localScopedBookmark::\(authorizedPath)"
    }

    private func loadLocalScopedBookmark(forAuthorizedPath authorizedPath: String) -> Data? {
        localScopedBookmarkDefaults.data(forKey: localScopedBookmarkKey(forAuthorizedPath: authorizedPath))
    }

    private func saveLocalScopedBookmark(_ data: Data, forAuthorizedPath authorizedPath: String) {
        localScopedBookmarkDefaults.set(data, forKey: localScopedBookmarkKey(forAuthorizedPath: authorizedPath))
    }

    private func removeLocalScopedBookmark(forAuthorizedPath authorizedPath: String) {
        localScopedBookmarkDefaults.removeObject(forKey: localScopedBookmarkKey(forAuthorizedPath: authorizedPath))
    }

    // In a sandboxed extension FileManager.default.homeDirectoryForCurrentUser
    // returns the container home (…/Library/Containers/<bundle id>/Data), not
    // the real user home — so we query the user database directly. This is
    // what the home-relative-path entitlement is evaluated against, so it is
    // also the right boundary for our "skip the bookmark dance" fast path.
    private static let realUserHomePath: String = {
        if let pw = getpwuid(getuid()),
           let home = pw.pointee.pw_dir.flatMap({ String(validatingUTF8: $0) }) {
            return URL(fileURLWithPath: home).standardizedFileURL.path
        }
        return NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
    }()

    private func isInsideHomeDirectory(_ url: URL) -> Bool {
        let homePath = FinderSync.realUserHomePath
        let targetPath = url.standardizedFileURL.path
        return targetPath == homePath || targetPath.hasPrefix(homePath + "/")
    }

    private func bestAuthorizedFolderEntry(for directoryURL: URL) -> SharedAuthorizedFolderEntry? {
        let targetPath = directoryURL.standardizedFileURL.path
        let entries = sharedAuthorizedFolderEntries()

        return entries
            .filter { entry in
                targetPath == entry.path || targetPath.hasPrefix(entry.path + "/")
            }
            .max { lhs, rhs in lhs.path.count < rhs.path.count }
    }

    private func sharedAuthorizedFolderEntries() -> [SharedAuthorizedFolderEntry] {
        let defaults = UserDefaults(suiteName: sharedDefaultsSuiteName) ?? .standard
        guard
            let data = defaults.data(forKey: sharedAuthorizedFolderEntriesKey),
            let entries = try? JSONDecoder().decode([SharedAuthorizedFolderEntry].self, from: data)
        else {
            return []
        }

        return entries
    }

    private func refreshMonitoredDirectories() {
        let controller = FIFinderSyncController.default()
        let homeDirectoryURL = URL(fileURLWithPath: FinderSync.realUserHomePath).standardizedFileURL
        let authorizedFolderURLs = sharedAuthorizedFolderEntries().map {
            URL(fileURLWithPath: $0.path).standardizedFileURL
        }

        var monitoredURLs: [URL] = [homeDirectoryURL]
        for url in authorizedFolderURLs where !monitoredURLs.contains(url) {
            monitoredURLs.append(url)
        }

        controller.directoryURLs = Set(monitoredURLs)
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

private enum FinderFileError: Error {
    case accessNotGranted(String)
}
