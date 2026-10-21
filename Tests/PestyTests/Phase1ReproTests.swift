import XCTest
@testable import Pesty

/// Minimal reproductions for the security review (docs/selfuse/01-security-review.md).
/// They exercise the operating-system behavior the findings depend on, not
/// ClipboardStore itself: its shared instance reads and writes the real
/// ~/Library/Application Support/Pesty and must never run under test.
final class Phase1ReproTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesty-repro-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Finding H2: a vnode source opened on store.json watches one inode. An
    /// atomic write replaces that inode, so a source that is not re-armed
    /// after the replacement never fires again, which is what the
    /// ignore-window early return in ClipboardStore.startWatching leaves behind.
    func testAtomicWriteOrphansAVnodeSourceThatIsNotRearmed() throws {
        let file = dir.appendingPathComponent("store.json")
        try Data("a".utf8).write(to: file, options: .atomic)

        let fd = open(file.path, O_EVTONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        let queue = DispatchQueue(label: "repro.watch")
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        let lock = NSLock()
        var events = 0
        let first = expectation(description: "first replacement is seen")
        source.setEventHandler {
            lock.lock(); events += 1; let n = events; lock.unlock()
            if n == 1 { first.fulfill() }
            // Deliberately not re-armed, mirroring the early return.
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        defer { source.cancel() }

        try Data("b".utf8).write(to: file, options: .atomic)
        wait(for: [first], timeout: 2)

        lock.lock(); let afterFirst = events; lock.unlock()
        try Data("c".utf8).write(to: file, options: .atomic)
        try Data("d".utf8).write(to: file, options: .atomic)
        Thread.sleep(forTimeInterval: 0.5)
        queue.sync {}

        lock.lock(); let afterMore = events; lock.unlock()
        XCTAssertEqual(afterMore, afterFirst,
                       "the orphaned source should see nothing after the inode it watched was replaced")
    }

    /// Finding A: appendingPathComponent does not stop "..", so a file name
    /// taken from an external store.json can point outside the images folder.
    func testImageFileNameWithDotDotEscapesImagesDirectory() {
        let images = dir.appendingPathComponent("Pesty/images", isDirectory: true)
        let escaped = images.appendingPathComponent("../../victim.txt").standardizedFileURL
        XCTAssertEqual(escaped.path, dir.appendingPathComponent("victim.txt").standardizedFileURL.path)
    }
}
