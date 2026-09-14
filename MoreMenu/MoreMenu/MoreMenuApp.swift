//
//  MoreMenuApp.swift
//  MoreMenu
//
//  Created by Robert Wildling on 2026-04-07.
//

import SwiftUI
import Foundation

@main
struct MoreMenuApp: App {
    @StateObject private var settings = SettingsStore()

    init() {
        let arguments = CommandLine.arguments
        guard arguments.count > 1, arguments[1] == "--import-legacy-settings" else { return }
        guard arguments.count == 3 else {
            Self.failImport("Expected one JSON settings argument")
        }
        do {
            guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MenuPreferences.suiteName) != nil else {
                Self.failImport("The signing identity does not authorize the shared settings container")
            }
            // Modern UserDefaults enqueues writes before set() returns. Do not use
            // synchronize(): it can report failure for unrelated search domains.
            try MenuPreferences.shared.importLegacySettings(Data(arguments[2].utf8))
            print("Shared settings are available; legacy preferences imported without replacing existing choices.")
            exit(EXIT_SUCCESS)
        } catch {
            Self.failImport(error.localizedDescription)
        }
    }

    private static func failImport(_ message: String) -> Never {
        FileHandle.standardError.write(Data("MoreMenu settings import failed: \(message)\n".utf8))
        exit(EXIT_FAILURE)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings)
        }
    }
}
