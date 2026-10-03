import Foundation

/// Finder consults the extension only for clicks inside its monitored folders.
/// The boot volume root also covers the Desktop background and home-rooted windows.
/// Other volumes are separate mounts and need their own entries.
enum FinderMonitoringScope {
    static let rootURL = URL(fileURLWithPath: "/", isDirectory: true)

    /// `excluding` releases volumes that are about to unmount, so Finder Sync cannot block ejecting them.
    static func directoryURLs(mountedVolumes: [URL], excluding unmountingVolumes: [URL] = []) -> Set<URL> {
        let excludedPaths = Set(unmountingVolumes.filter(\.isFileURL).map { normalized($0).path })
        var monitored: Set<URL> = [rootURL]
        for volume in mountedVolumes where volume.isFileURL {
            let volumeURL = normalized(volume)
            if !excludedPaths.contains(volumeURL.path) {
                monitored.insert(volumeURL)
            }
        }
        return monitored
    }

    /// Volume URLs arrive with and without a trailing slash; compare them by path.
    private static func normalized(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }
}
