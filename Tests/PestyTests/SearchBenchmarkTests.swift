import XCTest
@testable import Pesty

/// Before/after numbers for search over a 5,000-clip history. Prints a
/// summary line (grep "SEARCH-BENCH") so CI logs and local runs are easy to
/// compare; XCTest's measure blocks add their own averages.
final class SearchBenchmarkTests: XCTestCase {
    private static let historySize = 5_000
    /// The keystrokes of typing "zhongguo", then a Han query and a Latin one.
    private static let keystrokes = ["z", "zh", "zho", "zhon", "zhong", "zhongg", "zhonggu", "zhongguo",
                                     "中国", "report"]

    private static let clips: [ClipItem] = {
        var generator = SeededGenerator(seed: 42)
        let han = Array("的一是不了人我在有他这中大来上国个到说们为子和你地出道也时年得就那要下以生会自着去之过家学对可她里后小么心多天而能好都然没日于起还发成事只作当想看文无开手十用主行方又如前所本见经头面公同三已老从动两长知民样现分将外但身些与高意进把法此实回二理美点月明其种声全工己话儿者向情部正名定女问力机给等几很业最间新什打便位因重被走电四第门相次东政海口使教西再平真听世气信北少关并内加化由")
        let words = ["report", "meeting", "invoice", "https://example.com/a", "password", "Swift", "release",
                     "deadline", "TODO", "draft"]
        let apps = ["Safari", "Notes", "微信", "Xcode", "Mail"]
        return (0..<historySize).map { i in
            var text = ""
            let length = Int.random(in: 10...600, using: &generator)
            while text.count < length {
                if Bool.random(using: &generator) {
                    for _ in 0..<Int.random(in: 1...12, using: &generator) { text.append(han.randomElement(using: &generator)!) }
                } else {
                    text += " " + words.randomElement(using: &generator)! + " "
                }
            }
            return ClipItem(type: .text, text: text, sourceAppName: apps[i % apps.count])
        }
    }()

    func testLegacyFilterPerKeystroke() {
        let clips = Self.clips
        measure {
            for q in Self.keystrokes {
                let needle = q.lowercased()
                _ = clips.filter { $0.legacySearchableText.contains(needle) }
            }
        }
    }

    func testIndexedFilterPerKeystroke() {
        let indexes = Self.clips.map { SearchIndex(text: $0.searchSource) }
        measure {
            for q in Self.keystrokes {
                let query = SearchQuery(q)!
                _ = indexes.filter { $0.matches(query) }
            }
        }
    }

    func testIndexBuild() {
        let clips = Self.clips
        measure {
            _ = clips.map { SearchIndex(text: $0.searchSource) }
        }
    }

    func testSummary() {
        let clips = Self.clips
        let legacy = Self.time {
            for q in Self.keystrokes { _ = clips.filter { $0.legacySearchableText.contains(q.lowercased()) } }
        } / Double(Self.keystrokes.count)
        var indexes: [SearchIndex] = []
        let build = Self.time { indexes = clips.map { SearchIndex(text: $0.searchSource) } }
        let indexed = Self.time {
            for q in Self.keystrokes { let query = SearchQuery(q)!; _ = indexes.filter { $0.matches(query) } }
        } / Double(Self.keystrokes.count)
        print(String(format: "SEARCH-BENCH clips=%d legacy=%.2fms/keystroke indexed=%.2fms/keystroke build=%.0fms",
                     clips.count, legacy * 1000, indexed * 1000, build * 1000))
    }

    private static func time(_ body: () -> Void) -> TimeInterval {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }
}

/// Deterministic test data: the same 5,000 clips on every run and machine.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
