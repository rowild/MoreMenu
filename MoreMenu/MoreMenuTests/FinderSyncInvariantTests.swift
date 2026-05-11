//
//  FinderSyncInvariantTests.swift
//  MoreMenuTests
//
//  Guards a hard-won invariant about the Finder Sync extension that cannot be
//  caught by compile-time checks and is painful to catch manually in QA.
//
//  BACKGROUND: macOS Sonoma (14+) introduced an "App Management" privacy gate
//  that fires whenever a Finder Sync extension's `directoryURLs` cover paths
//  containing another app's Container data (e.g. `~/Library/Containers/
//  com.apple.TextEdit/`). In release 1.1.5 we briefly registered the real
//  user home — which implicitly covers every installed app's Container — and
//  that caused macOS to prompt the user every time TextEdit was launched, AND
//  suppressed the right-click menu items until consent was granted.
//
//  Release 1.2.1 registered the filesystem root, but Tahoe still recorded a
//  boot-time `SystemPolicyAppData` access for the Finder Sync process. The
//  current fix is to monitor visible top-level home folders while excluding
//  roots that contain app data, especially ~/Library and ~/Applications.
//
//  These tests pin the source-level shape of that registration so a future
//  refactor cannot silently re-introduce the regression without the CI build
//  failing.
//

import Testing
import Foundation

struct FinderSyncInvariantTests {
    private static var finderSyncSource: String {
        // The test binary lives inside DerivedData, so locate the source via
        // the repo root derived from this file's path.
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // MoreMenuTests
            .deletingLastPathComponent() // MoreMenu (Xcode project dir)
        let finderSyncURL = repoRoot
            .appendingPathComponent("MoreMenuExtension")
            .appendingPathComponent("FinderSync.swift")
        return (try? String(contentsOf: finderSyncURL, encoding: .utf8)) ?? ""
    }

    @Test("FinderSync does not register filesystem or home roots")
    func directoryURLsAvoidsBroadRoots() {
        let source = Self.finderSyncSource
        #expect(!source.isEmpty, "Could not locate FinderSync.swift source")

        let forbiddenRootLiteral = #"FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]"#
        #expect(
            !source.contains(forbiddenRootLiteral),
            "FinderSync must not register the filesystem root; Tahoe records boot-time AppData access for that scope."
        )

        #expect(
            source.contains("Self.monitoredDirectoryURLs()"),
            "FinderSync.init() should use the filtered monitored-directory list instead of a broad root."
        )
    }

    @Test("FinderSync excludes app-data roots from monitoring")
    func directoryURLsExcludesAppDataRoots() {
        let source = Self.finderSyncSource
        #expect(!source.isEmpty)

        #expect(source.contains(#""Library""#))
        #expect(source.contains(#""Applications""#))
        #expect(source.contains("excludedTopLevelHomeDirectoryNames"))
        #expect(source.contains("resourceValues?.isPackage != true"))
    }

    @Test("FinderSync assigns directoryURLs only in init")
    func directoryURLsIsNotReassignedDynamically() {
        let source = Self.finderSyncSource
        #expect(!source.isEmpty)

        // Count total assignments to directoryURLs. We allow exactly one in
        // init(). Dynamic reassignment based on user-home or authorized folders
        // is what tripped the App Management gate in 1.1.5.
        let assignments = source.components(separatedBy: ".directoryURLs = ").count - 1
        #expect(
            assignments == 1,
            "FinderSync must assign directoryURLs exactly once (in init). Found \(assignments) assignments."
        )
    }
}
