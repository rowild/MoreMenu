import AppKit
import Foundation
import Testing

struct FileCreationTests {
    @Test func existingContentsSurviveAndNamesAdvance() throws {
        let folder = try TemporaryFolder()
        let original = folder.url.appendingPathComponent("untitled.txt")
        let second = folder.url.appendingPathComponent("untitled_0001.txt")
        try Data("keep me".utf8).write(to: original)
        try Data("keep me too".utf8).write(to: second)
        let created = try DocumentFileCreator().create(in: folder.url, as: .plainText)
        #expect(created.lastPathComponent == "untitled_0002.txt")
        #expect(try String(contentsOf: original, encoding: .utf8) == "keep me")
        #expect(try String(contentsOf: second, encoding: .utf8) == "keep me too")
        #expect(try Data(contentsOf: created).isEmpty)
    }

    @Test func simultaneousCreatorsGetDistinctFiles() throws {
        let folder = try TemporaryFolder()
        let results = CreationResults()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            results.append(Result { try DocumentFileCreator().create(in: folder.url, as: .plainText) })
        }
        let urls = try results.values.map { try $0.get() }
        #expect(urls.count == 32)
        #expect(Set(urls).count == 32)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).count == 32)
    }

    @Test func richTextIsReadableAndOtherFormatsStartEmpty() throws {
        let folder = try TemporaryFolder()
        for kind in DocumentKind.allCases {
            let url = try DocumentFileCreator().create(in: folder.url, as: kind)
            let data = try Data(contentsOf: url)
            if kind == .richText {
                let document = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                #expect(document.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                #expect(data.isEmpty)
            }
        }
    }

    @Test func missingDestinationReportsFailure() throws {
        let folder = try TemporaryFolder()
        #expect(throws: (any Error).self) {
            try DocumentFileCreator().create(in: folder.url.appendingPathComponent("missing"), as: .plainText)
        }
    }

    @Test func targetResolutionDistinguishesFilesAndDirectories() throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appendingPathComponent("example.txt")
        try Data().write(to: file)
        #expect(try TargetDirectoryResolver.directory(for: folder.url) == folder.url)
        #expect(try TargetDirectoryResolver.directory(for: file) == folder.url)
        #expect(throws: (any Error).self) {
            try TargetDirectoryResolver.directory(for: folder.url.appendingPathComponent("missing"))
        }
    }
}

final class TemporaryFolder {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("MoreMenuTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

private final class CreationResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Result<URL, Error>] = []
    func append(_ value: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }
    var values: [Result<URL, Error>] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
