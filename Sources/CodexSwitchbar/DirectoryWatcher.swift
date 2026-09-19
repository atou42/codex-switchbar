#if os(macOS)
import Foundation
import Darwin

/// Watch the directory, not the auth file inode: Codex may atomically replace it.
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    init(url: URL, changed: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return } // The 30-second fallback timer remains active.
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
            eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let work = DispatchWorkItem(block: changed)
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }
    deinit { pending?.cancel(); source?.cancel() }
}
#endif
