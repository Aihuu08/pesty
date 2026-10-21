import Foundation

/// File names read from store.json (which another Mac can write when iCloud
/// Drive sync is on) are joined to the images folder and later deleted. Only
/// a single plain path component may ever be used that way.
enum StoredFileName {
    static func isSafe(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 255,
              name != ".", name != "..",
              !name.contains("/"), !name.contains("\0") else { return false }
        return true
    }

    /// The file inside `directory`, or nil when `name` is not a plain name
    /// or would resolve anywhere else.
    static func url(for name: String, in directory: URL) -> URL? {
        guard isSafe(name) else { return nil }
        let url = directory.appendingPathComponent(name, isDirectory: false)
        guard url.standardizedFileURL.deletingLastPathComponent().path
                == directory.standardizedFileURL.path else { return nil }
        return url
    }
}

extension ClipItem {
    /// The clip with an unsafe image file name dropped. The clip then shows
    /// as a missing image instead of pointing anywhere outside the store.
    func withSafeImageFileName() -> ClipItem {
        guard let name = imageFileName, !StoredFileName.isSafe(name) else { return self }
        var copy = self
        copy.imageFileName = nil
        return copy
    }
}
