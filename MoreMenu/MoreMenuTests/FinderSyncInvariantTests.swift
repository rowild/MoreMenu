import Foundation
import Testing

struct FinderSyncInvariantTests {
    @Test func monitoredDirectoriesExcludeBroadAndAppDataRoots() throws {
        let home = try TemporaryFolder()
        for name in ["Desktop", "Documents", "Projects", "Library", "Applications", ".hidden", "Example.app"] {
            try FileManager.default.createDirectory(at: home.url.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data().write(to: home.url.appendingPathComponent("a-file.txt"))
        let scope = HomeDirectoryScope(homeURL: home.url)
        let monitored = scope.monitoredDirectoryURLs()
        #expect(Set(monitored.map(\.lastPathComponent)) == ["Desktop", "Documents", "Projects"])
        #expect(!monitored.contains(home.url))
        #expect(!monitored.contains(URL(fileURLWithPath: "/")))
    }

    @Test func homeBoundaryDoesNotAcceptSiblingWithSamePrefix() throws {
        let home = try TemporaryFolder()
        let scope = HomeDirectoryScope(homeURL: home.url)
        #expect(scope.contains(home.url.appendingPathComponent("Documents")))
        #expect(!scope.contains(URL(fileURLWithPath: home.url.path + "-other/Documents")))
        #expect(!scope.contains(home.url.appendingPathComponent("../outside")))
    }

    @Test func finderRegistrationStillOccursOnlyOnce() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: project.appendingPathComponent("MoreMenuExtension/FinderSync.swift"), encoding: .utf8)
        #expect(source.components(separatedBy: ".directoryURLs = ").count - 1 == 1)
        #expect(source.contains("scope.monitoredDirectoryURLs()"))
    }
}
