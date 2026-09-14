import Foundation

struct DocumentFileCreator {
    /// Claim the filename in the write itself. Finder can run multiple extension instances.
    func create(in directory: URL, as kind: DocumentKind) throws -> URL {
        var counter = 0
        while true {
            let suffix = counter == 0 ? "" : "_" + String(format: "%04d", counter)
            let candidate = directory.appendingPathComponent("untitled\(suffix).\(kind.fileExtension)")
            do {
                try kind.initialContents.write(to: candidate, options: .withoutOverwriting)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                counter += 1
            }
        }
    }
}
