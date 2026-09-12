import Foundation

/// Where recordings live and how they are named. Pure helpers are static so they can be tested.
enum RecordingStore {
    /// Messages refuses attachments above roughly this size; surfaced as a warning in the editor.
    static let messagesAttachmentLimit: Int64 = 100_000_000

    static var directory: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return movies.appendingPathComponent("Snipcast", isDirectory: true)
    }

    static func ensureDirectory() throws -> URL {
        let dir = directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func recordingName(for date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Snipcast \(f.string(from: date)).mp4"
    }

    static func newRecordingURL(date: Date = .now) throws -> URL {
        try ensureDirectory().appendingPathComponent(recordingName(for: date))
    }

    static func trimmedURL(for source: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = source.deletingLastPathComponent().appendingPathComponent("\(base) trimmed.mp4")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = source.deletingLastPathComponent().appendingPathComponent("\(base) trimmed \(n).mp4")
            n += 1
        }
        return candidate
    }

    static func fileSize(of url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func formattedSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    static func exceedsMessagesLimit(_ bytes: Int64) -> Bool {
        bytes > messagesAttachmentLimit
    }
}
