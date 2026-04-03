import Foundation

/// Watches a file for modifications using FSEvents (directory-level monitoring).
/// Survives atomic saves (delete + rename) because FSEvents is path-based, not inode-based.
final class FileWatcher: @unchecked Sendable {
    private nonisolated(unsafe) var stream: FSEventStreamRef?
    private let filePath: String
    private let dirPath: String
    private let onChange: @Sendable (URL) -> Void
    private var lastModDate: Date?

    init(url: URL, onChange: @MainActor @escaping (URL) -> Void) {
        self.filePath = url.path
        self.dirPath = url.deletingLastPathComponent().path
        self.onChange = { url in DispatchQueue.main.async { onChange(url) } }
        self.lastModDate = Self.modificationDate(path: filePath)
    }

    func start() {
        stop()

        // Shared mutable state for the callback
        final class WatcherState: @unchecked Sendable {
            var lastModDate: Date?
            let filePath: String
            let onChange: @Sendable (URL) -> Void
            init(filePath: String, lastModDate: Date?, onChange: @escaping @Sendable (URL) -> Void) {
                self.filePath = filePath
                self.lastModDate = lastModDate
                self.onChange = onChange
            }
        }
        let state = WatcherState(filePath: self.filePath, lastModDate: self.lastModDate, onChange: self.onChange)

        var context = FSEventStreamContext()
        context.info = Unmanaged.passRetained(state).toOpaque()
        context.release = { info in
            guard let info else { return }
            Unmanaged<WatcherState>.fromOpaque(info).release()
        }
        context.retain = { info -> UnsafeRawPointer? in
            guard let info else { return nil }
            return UnsafeRawPointer(Unmanaged<WatcherState>.fromOpaque(info).retain().toOpaque())
        }

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let state = Unmanaged<WatcherState>.fromOpaque(info).takeUnretainedValue()
            let newDate = FileWatcher.modificationDate(path: state.filePath)
            guard let newDate, newDate != state.lastModDate else { return }
            state.lastModDate = newDate
            state.onChange(URL(fileURLWithPath: state.filePath))
        }

        guard let newStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [dirPath as CFString] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(newStream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(newStream)
        stream = newStream
    }

    private static func modificationDate(path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    func stop() {
        guard let existing = stream else { return }
        stream = nil
        FSEventStreamStop(existing)
        FSEventStreamInvalidate(existing)
        FSEventStreamRelease(existing)
    }

    deinit {
        stop()
    }
}

/// Manages security-scoped bookmarks for parent directories.
/// Allows re-reading files after atomic saves in sandboxed apps.
enum DirectoryBookmarks {
    private static let key = "directoryBookmarks"

    /// Save a security-scoped bookmark for the parent directory of a file URL.
    static func saveBookmark(for fileURL: URL) {
        saveBookmark(forDirectory: fileURL.deletingLastPathComponent())
    }

    /// Save a security-scoped bookmark for a directory URL (from NSOpenPanel).
    static func saveBookmark(forDirectory dir: URL) {
        guard let data = try? dir.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var bookmarks = loadAllBookmarks()
        bookmarks[dir.path] = data
        UserDefaults.standard.set(bookmarks, forKey: key)
    }

    /// Start accessing the security-scoped parent directory of a file URL.
    /// Returns the directory URL if access was granted (caller must call stopAccessing when done).
    @discardableResult
    static func startAccessing(for fileURL: URL) -> URL? {
        let dirPath = fileURL.deletingLastPathComponent().path
        let bookmarks = loadAllBookmarks()
        guard let data = bookmarks[dirPath] else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale {
            if let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                var bookmarks = loadAllBookmarks()
                bookmarks[dirPath] = fresh
                UserDefaults.standard.set(bookmarks, forKey: key)
            }
        }
        if url.startAccessingSecurityScopedResource() {
            return url
        }
        return nil
    }

    /// Check if a saved bookmark exists for the parent directory of a file URL.
    static func hasBookmark(for fileURL: URL) -> Bool {
        let dirPath = fileURL.deletingLastPathComponent().path
        return loadAllBookmarks()[dirPath] != nil
    }

    static func stopAccessing(_ url: URL?) {
        url?.stopAccessingSecurityScopedResource()
    }

    private static func loadAllBookmarks() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
    }
}
