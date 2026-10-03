import Foundation
import Testing

struct FinderSyncInvariantTests {
    private let root = URL(fileURLWithPath: "/", isDirectory: true)

    @Test func bootVolumeRootIsAlwaysMonitored() {
        #expect(FinderMonitoringScope.directoryURLs(mountedVolumes: []) == [root])
    }

    @Test func eachMountedVolumeIsMonitoredOnce() {
        let volumes = [URL(string: "file:///")!, URL(string: "file:///Volumes/Work/")!,
                       URL(fileURLWithPath: "/Volumes/Work"), URL(string: "file:///Volumes/My%20Share/")!]
        let monitored = FinderMonitoringScope.directoryURLs(mountedVolumes: volumes)
        #expect(Set(monitored.map(\.path)) == ["/", "/Volumes/Work", "/Volumes/My Share"])
        #expect(monitored.count == 3)
    }

    @Test func unmountingVolumeIsReleasedButRootStays() {
        let work = URL(string: "file:///Volumes/Work/")!
        let monitored = FinderMonitoringScope.directoryURLs(
            mountedVolumes: [root, work], excluding: [URL(fileURLWithPath: "/Volumes/Work")])
        #expect(monitored == [root])
        #expect(FinderMonitoringScope.directoryURLs(mountedVolumes: [root], excluding: [root]) == [root])
    }

    @Test func nonFileURLsAreIgnored() {
        let monitored = FinderMonitoringScope.directoryURLs(mountedVolumes: [URL(string: "smb://server/share")!])
        #expect(monitored == [root])
    }

    @Test func finderRegistrationUsesTheMonitoringScope() throws {
        let source = try extensionSource()
        #expect(source.components(separatedBy: ".directoryURLs = ").count - 1 == 1)
        #expect(source.contains("FinderMonitoringScope.directoryURLs("))
    }

    /// A metadata read in a protected folder can raise a privacy prompt on a mere right-click.
    @Test func menuConstructionDoesNotReadFileMetadata() throws {
        let source = try extensionSource()
        let menuStart = try #require(source.range(of: "override func menu(for menuKind: FIMenuKind)"))
        let menuEnd = try #require(source.range(of: "// MARK: - Menu action", range: menuStart.upperBound..<source.endIndex))
        let menuBody = source[menuStart.upperBound..<menuEnd.lowerBound]
        for diskRead in ["targetDirectory(", "TargetDirectoryResolver", "resourceValues"] {
            #expect(!menuBody.contains(diskRead), "menu(for:) must not call \(diskRead)")
        }
    }

    private func extensionSource() throws -> String {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: project.appendingPathComponent("MoreMenuExtension/FinderSync.swift"), encoding: .utf8)
    }
}
