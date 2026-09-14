import Foundation

struct TargetDirectoryResolver {
    static func directory(for url: URL) throws -> URL {
        guard url.isFileURL else { throw ResolutionError.notFileURL }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard let isDirectory = values.isDirectory else { throw ResolutionError.unknownFileType }
        return isDirectory ? url : url.deletingLastPathComponent()
    }

    enum ResolutionError: LocalizedError {
        case notFileURL
        case unknownFileType

        var errorDescription: String? {
            "MoreMenu could not determine the destination folder. Open the folder in Finder and try again."
        }
    }
}
