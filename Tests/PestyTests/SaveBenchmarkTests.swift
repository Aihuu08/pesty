import AppKit
import XCTest
@testable import Pesty

/// What one store.json save costs with a 5,000-clip history: every capture
/// re-encodes and rewrites the whole file. Prints a summary line (grep
/// "SAVE-BENCH"). Images are separate files and not part of this.
final class SaveBenchmarkTests: XCTestCase {
    /// Mirrors ClipboardStore.Snapshot, which is private; same JSON shape.
    private struct Snapshot: Codable {
        var history: [ClipItem]
        var pinboards: [Pinboard]
    }

    private static let snapshot: Snapshot = {
        var generator = SeededGenerator(seed: 7)
        let sentence = "The quick brown fox jumps over the lazy dog. 敏捷的棕色狐狸跳过了懒狗。"
        let rtf: Data = {
            let s = NSAttributedString(string: String(repeating: sentence, count: 20),
                                       attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            return s.rtf(from: NSRange(location: 0, length: s.length)) ?? Data()
        }()
        let html = Data(("<p><b>" + String(repeating: sentence, count: 200) + "</b></p>").utf8)
        let history: [ClipItem] = (0..<5_000).map { i in
            let text = String(repeating: sentence, count: Int.random(in: 1...12, using: &generator))
            switch i % 20 {
            case 0, 1, 2: return ClipItem(type: .richText, text: text, rtfData: rtf, sourceAppName: "Pages")
            case 3: return ClipItem(type: .text, text: text, htmlData: html, sourceAppName: "Safari")
            case 4, 5: return ClipItem(type: .link, text: "https://example.com/\(i)", sourceAppName: "Safari")
            case 6: return ClipItem(type: .image, imageFileName: "\(UUID().uuidString).png", imageHash: "\(i)")
            default: return ClipItem(type: .text, text: text, sourceAppName: "Notes")
            }
        }
        return Snapshot(history: history, pinboards: [])
    }()

    func testEncodeAndWrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pesty-save-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = Data()
        let encode = Self.time { data = try! JSONEncoder().encode(Self.snapshot) }
        let write = Self.time { try! data.write(to: url, options: .atomic) }
        let decode = Self.time { _ = try! JSONDecoder().decode(Snapshot.self, from: data) }
        print(String(format: "SAVE-BENCH clips=%d bytes=%d encode=%.0fms write=%.0fms decode=%.0fms",
                     Self.snapshot.history.count, data.count, encode * 1000, write * 1000, decode * 1000))
        XCTAssertGreaterThan(data.count, 0)
    }

    private static func time(_ body: () -> Void) -> TimeInterval {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }
}
