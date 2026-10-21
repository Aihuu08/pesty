import Foundation

/// Calls back when a file changes or is replaced.
///
/// A vnode source watches one inode, and an atomic write (ours, or iCloud
/// Drive delivering another Mac's copy) swaps the inode out from under it.
/// So the source is re-armed on the path after every event, before the
/// callback runs, and a callback that decides to ignore an event can never
/// leave the watch orphaned again.
final class FileChangeWatcher {
    private let url: URL
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var stopped = true

    /// While the path is briefly missing mid-replacement, retry opening it
    /// this often, this many times.
    private static let reopenDelay: TimeInterval = 0.25
    private static let reopenAttempts = 20

    init(url: URL, queue: DispatchQueue = .main, onChange: @escaping () -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
    }

    deinit { source?.cancel() }

    func start() {
        stopped = false
        arm(attemptsLeft: Self.reopenAttempts, notify: false)
    }

    func stop() {
        stopped = true
        source?.cancel()
        source = nil
    }

    private func arm(attemptsLeft: Int, notify: Bool) {
        source?.cancel()
        source = nil
        guard !stopped else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            guard attemptsLeft > 0 else { return }
            queue.asyncAfter(deadline: .now() + Self.reopenDelay) { [weak self] in
                self?.arm(attemptsLeft: attemptsLeft - 1, notify: notify)
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: queue)
        src.setEventHandler { [weak self] in
            guard let self, !self.stopped else { return }
            self.arm(attemptsLeft: Self.reopenAttempts, notify: true)
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
        // A replacement that reopened late still counts as a change.
        if notify { onChange() }
    }
}
