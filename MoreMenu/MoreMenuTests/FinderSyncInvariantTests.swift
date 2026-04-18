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
//  The fix was to register `FIFinderSyncController.default().directoryURLs =
//  [URL(fileURLWithPath: "/")]`. The filesystem-root registration is a special
//  mode that macOS does NOT classify as cross-app data access.
//
//  These tests pin that literal in source so a future refactor cannot silently
//  re-introduce the regression without the CI build failing.
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

    @Test("FinderSync registers ONLY the filesystem root for monitoring")
    func directoryURLsIsFilesystemRoot() {
        let source = Self.finderSyncSource
        #expect(!source.isEmpty, "Could not locate FinderSync.swift source")

        // The invariant literal. Changing this without updating the test is a
        // deliberate signal to stop and re-read the comment above.
        let expected = #"FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]"#
        #expect(
            source.contains(expected),
            "FinderSync.init() must register [URL(fileURLWithPath: \"/\")] as its monitored directories. Any other value (e.g. user home) triggers the Sonoma App Management prompt when other apps are launched."
        )
    }

    @Test("FinderSync does NOT re-assign directoryURLs per menu invocation")
    func directoryURLsIsNotReassignedDynamically() {
        let source = Self.finderSyncSource
        #expect(!source.isEmpty)

        // Count total assignments to directoryURLs. We allow exactly one — the
        // init() call. Dynamic reassignment based on user-home or authorized
        // folders is what tripped the App Management gate in 1.1.5.
        let assignments = source.components(separatedBy: ".directoryURLs = ").count - 1
        #expect(
            assignments == 1,
            "FinderSync must assign directoryURLs exactly once (in init). Found \(assignments) assignments."
        )
    }
}
