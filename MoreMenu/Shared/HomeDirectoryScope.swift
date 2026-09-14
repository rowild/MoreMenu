import Foundation

/// Limits Finder monitoring independently of sandbox/TCC authorization.
struct HomeDirectoryScope {
    let homeURL: URL

    init(homeURL: URL) {
        self.homeURL = homeURL.standardizedFileURL
    }

    static var current: HomeDirectoryScope {
        // A sandboxed process's NSHomeDirectory points into its own container.
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else {
            preconditionFailure("Could not determine the user's login home")
        }
        return HomeDirectoryScope(homeURL: URL(fileURLWithPath: String(cString: home), isDirectory: true))
    }

    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == homeURL.path || path.hasPrefix(homeURL.path + "/")
    }

    private static let excludedTopLevelHomeDirectoryNames: Set<String> = [
        "Applications",
        "Library"
    ]

    private static let fallbackTopLevelHomeDirectoryNames = [
        "Desktop",
        "Documents",
        "Downloads",
        "Movies",
        "Music",
        "Pictures",
        "Public"
    ]

    func monitoredDirectoryURLs() -> Set<URL> {
        var seenPaths = Set<String>()
        var monitoredURLs: [URL] = []

        func appendIfAllowed(_ url: URL) {
            let standardizedURL = url.standardizedFileURL
            let path = standardizedURL.path
            guard path != homeURL.path else { return }
            guard path.hasPrefix(homeURL.path + "/") else { return }
            guard seenPaths.insert(path).inserted else { return }
            monitoredURLs.append(standardizedURL)
        }

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        if let homeChildren = try? FileManager.default.contentsOfDirectory(
            at: homeURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) {
            for childURL in homeChildren.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard !Self.excludedTopLevelHomeDirectoryNames.contains(childURL.lastPathComponent) else {
                    continue
                }

                let resourceValues = try? childURL.resourceValues(forKeys: resourceKeys)
                guard resourceValues?.isDirectory == true, resourceValues?.isPackage != true else {
                    continue
                }

                appendIfAllowed(childURL)
            }
        }

        for directoryName in Self.fallbackTopLevelHomeDirectoryNames {
            var isDirectory: ObjCBool = false
            let fallbackURL = homeURL.appendingPathComponent(directoryName, isDirectory: true)
            if FileManager.default.fileExists(atPath: fallbackURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                appendIfAllowed(fallbackURL)
            }
        }

        return Set(monitoredURLs)
    }

}
