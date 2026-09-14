//
//  FinderSync.swift
//  MoreMenuExtension
//
//  Created by Robert Wildling on 2026-04-07.
//
//  File creation is limited to the user home by the extension sandbox entitlement.
//  Shared preferences use a Team-ID-prefixed App Group authorized by the signer.
//  See DEVELOPER.md for the separate monitoring, sandbox, and TCC constraints.

import Cocoa
import FinderSync
import OSLog

class FinderSync: FIFinderSync {
    private let logger = Logger(subsystem: "GMX.MoreMenu.MoreMenuExtension", category: "FinderSync")
    private let scope = HomeDirectoryScope.current
    private let fileCreator = DocumentFileCreator()
    private var currentMenuKind: FIMenuKind = .contextualMenuForContainer

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = scope.monitoredDirectoryURLs()
    }

    // MARK: - FIFinderSync overrides

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForItems else {
            return NSMenu(title: "")
        }

        let menu = NSMenu(title: "")
        let enabledKinds = MenuPreferences.shared.activeKinds

        guard let target = targetDirectory(for: menuKind), !enabledKinds.isEmpty else {
            return menu
        }

        // Hide the menu in locations the sandbox entitlement can't reach:
        // filesystem root `/`, `/Volumes/*`, other users' homes, `/tmp`,
        // `/Applications`, etc. The user gets no false affordance for file
        // creation that would silently fail.
        guard scope.contains(target) else {
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
            showCreationError("MoreMenu could not determine the destination folder. Open the folder in Finder and try again.")
            return
        }

        guard scope.contains(targetURL) else {
            logger.error("Refusing to create file outside user home: \(targetURL.path, privacy: .public)")
            NSSound.beep()
            return
        }

        logger.log("Creating \(kind.fileExtension, privacy: .public) file in: \(targetURL.path, privacy: .public)")

        do {
            let createdURL = try fileCreator.create(in: targetURL, as: kind)
            logger.log("Successfully created: \(createdURL.path, privacy: .public)")
            presentCreatedFile(createdURL)
        } catch {
            logger.error("Failed to create file in \(targetURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            showCreationError("Could not create a file in \(targetURL.lastPathComponent). \(error.localizedDescription)")
        }
    }

    private func showCreationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "File could not be created"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Target directory resolution

    private func targetDirectory(for menuKind: FIMenuKind) -> URL? {
        if let targetedURL = FIFinderSyncController.default().targetedURL() {
            do {
                return try TargetDirectoryResolver.directory(for: targetedURL)
            } catch {
                logger.error("Could not resolve target directory: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        guard menuKind == .contextualMenuForContainer else { return nil }
        return currentInsertionLocation()
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

    // MARK: - File presentation

    private func presentCreatedFile(_ fileURL: URL) {
        if !NSWorkspace.shared.open(fileURL) {
            logger.error("Could not open \(fileURL.path, privacy: .public); selecting in Finder instead")
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private func kind(forMenuTitle title: String) -> DocumentKind? {
        DocumentKind.allCases.first { $0.menuTitle == title }
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
