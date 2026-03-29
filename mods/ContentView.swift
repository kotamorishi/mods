import Foundation
import os

/// Watches a file for modifications using GCD dispatch source.
/// Thread-safe: all access to `source` is protected by a lock.
final class FileWatcher: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<DispatchSourceFileSystemObject?>(initialState: nil)
    private let url: URL
    private let onChange: @Sendable (URL) -> Void

    init(url: URL, onChange: @MainActor @escaping (URL) -> Void) {
        self.url = url
        self.onChange = { url in DispatchQueue.main.async { onChange(url) } }
    }

    func start() {
        stop() // Prevent fd leak if start() called multiple times

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        newSource.setEventHandler { [onChange] in
            // Resolve current path from fd (handles renames)
            var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let currentURL: URL
            if fcntl(fd, F_GETPATH, &buf) != -1 {
                currentURL = URL(fileURLWithPath: String(cString: buf))
            } else {
                return // fd invalid, file likely deleted
            }
            onChange(currentURL)
        }
        newSource.setCancelHandler {
            close(fd)
        }
        newSource.resume()

        lock.withLock { $0 = newSource }
    }

    func stop() {
        let existing = lock.withLock { source -> DispatchSourceFileSystemObject? in
            let old = source
            source = nil
            return old
        }
        existing?.cancel()
    }

    deinit {
        stop()
    }
}
