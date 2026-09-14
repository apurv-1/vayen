import Foundation

/// Bounded file reads for cheap session digests. Read-only; never mutates.
public enum PartialFileReader {

    /// Up to `limit` bytes from the start of the file, split into complete
    /// newline-terminated lines. A trailing partial line is dropped.
    /// Returns nil when the file cannot be read.
    public static func headLines(url: URL, limit: Int) -> [Data]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return nil }
        return splitCompleteLines(data, dropLeadingPartial: false)
    }

    /// Up to `limit` bytes from the end of the file, split into complete lines.
    /// The leading partial line (where the slice cut mid-record) is dropped.
    /// Returns nil when the file cannot be read.
    public static func tailLines(url: URL, limit: Int) -> [Data]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return [] }
        let offset = size > UInt64(limit) ? size - UInt64(limit) : 0
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd() else { return nil }
            // If we sliced mid-file, the first fragment is incomplete.
            return splitCompleteLines(data, dropLeadingPartial: offset > 0)
        } catch {
            return nil
        }
    }

    private static func splitCompleteLines(_ data: Data, dropLeadingPartial: Bool) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        if dropLeadingPartial {
            guard let nl = data.firstIndex(of: 0x0A) else { return [] }
            start = data.index(after: nl)
        }
        while start < data.endIndex, let nl = data[start...].firstIndex(of: 0x0A) {
            let line = data[start..<nl]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            start = data.index(after: nl)
        }
        return lines
    }
}
