import XCTest
@testable import Pesty

final class FileChangeWatcherTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesty-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// The iCloud Drive bug: every atomic save replaces the inode, and the
    /// watch must keep following the path through all of them.
    func testKeepsReportingAcrossAtomicReplacements() throws {
        let file = dir.appendingPathComponent("store.json")
        try Data("0".utf8).write(to: file, options: .atomic)
        let queue = DispatchQueue(label: "watch.test")
        let changes = expectation(description: "each replacement is seen")
        changes.expectedFulfillmentCount = 3
        changes.assertForOverFulfill = false
        let watcher = FileChangeWatcher(url: file, queue: queue) { changes.fulfill() }
        queue.sync { watcher.start() }

        for i in 1...3 {
            try Data("\(i)".utf8).write(to: file, options: .atomic)
            Thread.sleep(forTimeInterval: 0.3)
        }
        wait(for: [changes], timeout: 5)
        queue.sync { watcher.stop() }
    }

    func testStopEndsCallbacks() throws {
        let file = dir.appendingPathComponent("store.json")
        try Data("0".utf8).write(to: file, options: .atomic)
        let queue = DispatchQueue(label: "watch.test.stop")
        let lock = NSLock()
        var count = 0
        let watcher = FileChangeWatcher(url: file, queue: queue) { lock.lock(); count += 1; lock.unlock() }
        queue.sync { watcher.start() }
        queue.sync { watcher.stop() }
        try Data("1".utf8).write(to: file, options: .atomic)
        Thread.sleep(forTimeInterval: 0.5)
        queue.sync {}
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(count, 0)
    }
}

final class StoredFileNameTests: XCTestCase {
    func testRejectsAnythingButAPlainName() {
        XCTAssertTrue(StoredFileName.isSafe("5F1C2A8E-0000-4000-8000-000000000000.png"))
        XCTAssertTrue(StoredFileName.isSafe("image.png"))
        for bad in ["", ".", "..", "../x.png", "../../Documents", "a/b.png", "/etc/passwd", "x\0.png",
                    String(repeating: "a", count: 256)] {
            XCTAssertFalse(StoredFileName.isSafe(bad), bad)
        }
    }

    func testURLStaysInsideTheDirectory() {
        let images = URL(fileURLWithPath: "/tmp/pesty-test/images", isDirectory: true)
        XCTAssertEqual(StoredFileName.url(for: "a.png", in: images)?.path, "/tmp/pesty-test/images/a.png")
        XCTAssertNil(StoredFileName.url(for: "../a.png", in: images))
        XCTAssertNil(StoredFileName.url(for: "..", in: images))
    }

    func testUnsafeImageNamesAreDroppedFromClips() {
        let bad = ClipItem(type: .image, imageFileName: "../../victim", imageHash: "h")
        XCTAssertNil(bad.withSafeImageFileName().imageFileName)
        let good = ClipItem(type: .image, imageFileName: "ok.png", imageHash: "h")
        XCTAssertEqual(good.withSafeImageFileName().imageFileName, "ok.png")
    }
}
