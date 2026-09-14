import Foundation
import Testing
@testable import VayenCore

@Suite("Incremental transcript tailer")
struct TranscriptTailerTests {

    private func tempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vayen-tail-\(UUID().uuidString).jsonl")
        try "".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func overwrite(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func readsCompleteLinesAndRetainsPartial() async throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let tailer = TranscriptTailer()
        var cursor = TailCursor(fileKey: "main")

        // Write one complete record + a partial second record.
        try append("{\"type\":\"user\",\"uuid\":\"1\"}\n{\"type\":\"assista", to: url)
        var read = await tailer.read(url: url, cursor: cursor)
        #expect(read.lines.count == 1)
        #expect(read.status == .appended)
        #expect(read.cursor.pendingBytes == Data("{\"type\":\"assista".utf8))
        cursor = read.cursor

        // Complete the partial record; only the completed line is emitted.
        try append("nt\",\"uuid\":\"2\"}\n", to: url)
        read = await tailer.read(url: url, cursor: cursor)
        #expect(read.lines.count == 1)
        #expect(String(data: read.lines[0].data, encoding: .utf8) == "{\"type\":\"assista" + "nt\",\"uuid\":\"2\"}")
        #expect(read.cursor.pendingBytes.isEmpty)
    }

    @Test func truncationReparsesInNewGeneration() async throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let tailer = TranscriptTailer()
        try append("{\"a\":1}\n{\"a\":2}\n", to: url)
        var read = await tailer.read(url: url, cursor: TailCursor(fileKey: "main"))
        #expect(read.lines.count == 2)

        // Truncate the file in place.
        try overwrite("{\"b\":1}\n", to: url)
        read = await tailer.read(url: url, cursor: read.cursor)
        #expect(read.status == .reparsed)
        #expect(read.generation == 1)
        #expect(read.lines.count == 1)
        #expect(read.lines[0].recordIndex == 0)
    }

    @Test func fileReplacementReparses() async throws {
        let root = try Fixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("f.jsonl")
        try "{\"a\":1}\n".write(to: url, atomically: true, encoding: .utf8)

        let tailer = TranscriptTailer()
        var read = await tailer.read(url: url, cursor: TailCursor(fileKey: "main"))
        #expect(read.lines.count == 1)

        // Replace via atomic rename (new inode), as Claude Code would.
        let tmp = root.appendingPathComponent("f.tmp")
        try "{\"z\":1}\n{\"z\":2}\n".write(to: tmp, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)

        read = await tailer.read(url: url, cursor: read.cursor)
        #expect(read.status == .reparsed)
        #expect(read.generation == 1)
        #expect(read.lines.count == 2)
    }

    @Test func missingFileReportsMissing() async {
        let tailer = TranscriptTailer()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        let read = await tailer.read(url: url, cursor: TailCursor(fileKey: "main"))
        #expect(read.status == .missing)
    }

    @Test func unchangedFileReportsUnchanged() async throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let tailer = TranscriptTailer()
        try append("{\"a\":1}\n", to: url)
        var read = await tailer.read(url: url, cursor: TailCursor(fileKey: "main"))
        read = await tailer.read(url: url, cursor: read.cursor)
        #expect(read.status == .unchanged)
        #expect(read.lines.isEmpty)
    }
}
