import Foundation

/// Watches a file for modifications using GCD dispatch source.
final class FileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @MainActor @escaping () -> Void) {
        self.url = url
        self.onChange = { DispatchQueue.main.async { onChange() } }
    }

    func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [onChange] in
            onChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
