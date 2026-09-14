import Foundation

public enum TailStatus: String, Sendable {
    /// New complete records were emitted.
    case appended
    /// Nothing new since the cursor.
    case unchanged
    /// File was replaced (new inode) or truncated; cursor was reset and the
    /// file reparsed from the start. Emitted lines belong to the new generation.
    case reparsed
    /// File does not exist or is unreadable.
    case missing
}

public struct TailReadResult: Sendable {
    public var status: TailStatus
    /// Complete newline-terminated records in byte order, with record indices.
    public var lines: [(recordIndex: Int, data: Data)]
    public var cursor: TailCursor
    public var generation: Int

    public init(status: TailStatus, lines: [(recordIndex: Int, data: Data)], cursor: TailCursor, generation: Int) {
        self.status = status
        self.lines = lines
        self.cursor = cursor
        self.generation = generation
    }
}

struct FileIdentity: Equatable, Sendable {
    var device: UInt64
    var inode: UInt64
    var size: UInt64
}

/// Incremental reader for JSONL transcript files.
///
/// Guarantees:
/// - Only complete newline-terminated records are emitted.
/// - A partial trailing write is retained as `pendingBytes` until its newline arrives.
/// - File replacement (new inode) and truncation (size < offset) reset the cursor
///   and bump the generation rather than producing garbage.
/// - Sources are opened read-only and are never mutated.
public actor TranscriptTailer {

    private var identities: [String: FileIdentity] = [:]
    private var generations: [String: Int] = [:]

    public init() {}

    public func reset(fileKey: String) {
        identities.removeValue(forKey: fileKey)
        generations.removeValue(forKey: fileKey)
    }

    /// Read any newly appended complete records after `cursor`.
    /// Pass a fresh `TailCursor(fileKey:)` for a full read of the file.
    public func read(url: URL, cursor: TailCursor) -> TailReadResult {
        let fileKey = cursor.fileKey
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            return TailReadResult(status: .missing, lines: [], cursor: cursor, generation: generations[fileKey] ?? 0)
        }

        let identity = currentIdentity(url: url, size: size)
        var generation = generations[fileKey] ?? 0
        var byteOffset = cursor.byteOffset
        var recordIndex = cursor.recordIndex
        var pending = cursor.pendingBytes
        var status: TailStatus = .appended

        let knownIdentity = identities[fileKey]
        if knownIdentity != identity {
            // New file at this path, or first observation.
            if knownIdentity != nil || byteOffset > 0 {
                generation += 1
                status = .reparsed
            }
            byteOffset = 0
            recordIndex = 0
            pending = Data()
        } else if size < byteOffset {
            // Truncated in place: start over in a new generation.
            generation += 1
            byteOffset = 0
            recordIndex = 0
            pending = Data()
            status = .reparsed
        }

        identities[fileKey] = identity
        generations[fileKey] = generation

        guard size > byteOffset else {
            let newCursor = TailCursor(
                fileKey: fileKey, generation: generation, byteOffset: byteOffset,
                recordIndex: recordIndex, pendingBytes: pending,
                recentEventIDs: cursor.recentEventIDs
            )
            return TailReadResult(status: status == .reparsed ? .reparsed : .unchanged, lines: [], cursor: newCursor, generation: generation)
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return TailReadResult(status: .missing, lines: [], cursor: cursor, generation: generation)
        }
        defer { try? handle.close() }

        var lines: [(Int, Data)] = []
        do {
            try handle.seek(toOffset: byteOffset)
            let chunk = try handle.readToEnd() ?? Data()
            let buffer = pending + chunk
            var consumed = 0
            while let nl = buffer[consumed...].firstIndex(of: 0x0A) {
                let line = buffer[consumed..<nl]
                consumed = nl + 1
                // Skip blank lines rather than counting them as records.
                if line.isEmpty || line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) {
                    continue
                }
                lines.append((recordIndex, Data(line)))
                recordIndex += 1
            }
            pending = Data(buffer[consumed...])
            byteOffset = size
        } catch {
            return TailReadResult(status: .missing, lines: [], cursor: cursor, generation: generation)
        }

        let newCursor = TailCursor(
            fileKey: fileKey, generation: generation, byteOffset: byteOffset,
            recordIndex: recordIndex, pendingBytes: pending,
            recentEventIDs: cursor.recentEventIDs
        )
        return TailReadResult(status: status, lines: lines, cursor: newCursor, generation: generation)
    }

    private func currentIdentity(url: URL, size: UInt64) -> FileIdentity {
        var device: UInt64 = 0
        var inode: UInt64 = 0
        if let handle = try? FileHandle(forReadingFrom: url) {
            var info = stat()
            if fstat(handle.fileDescriptor, &info) == 0 {
                device = UInt64(info.st_dev)
                inode = UInt64(info.st_ino)
            }
            try? handle.close()
        }
        return FileIdentity(device: device, inode: inode, size: size)
    }
}
