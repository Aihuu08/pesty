import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A clip's searchable text, normalized once so a keystroke only runs byte
/// substring checks instead of re-transforming the whole history.
///
/// Matching is forgiving on purpose: case, full-width/half-width forms and
/// diacritics are folded away, Traditional Chinese is folded to Simplified,
/// and Han characters can also be found by full pinyin ("nihao") or by
/// initials ("nh"). Polyphonic characters only get their default reading,
/// so 重庆 is indexed as "zhongqing", not "chongqing".
struct SearchIndex: Sendable {
    /// The source text, folded, as UTF-8.
    let folded: ContiguousArray<UInt8>
    /// Han characters as toneless pinyin syllables, everything else folded;
    /// whitespace dropped. Empty when the text has no Han characters.
    let pinyin: ContiguousArray<UInt8>
    /// Han characters as the first letter of their syllable, everything else
    /// folded; whitespace dropped. Empty when the text has no Han characters.
    let initials: ContiguousArray<UInt8>

    /// Pinyin is only derived for this many leading scalars, which keeps a
    /// pasted book from costing seconds; folded text always covers everything.
    static let pinyinScalarLimit = 10_000

    init(text: String) {
        var folded = ContiguousArray<UInt8>()
        var pinyin = ContiguousArray<UInt8>()
        var initials = ContiguousArray<UInt8>()
        HanReadings.shared.transcribe(SearchFolding.foldWithoutHan(text),
                                      folded: &folded,
                                      pinyin: &pinyin,
                                      initials: &initials,
                                      pinyinLimit: Self.pinyinScalarLimit)
        self.folded = folded
        self.pinyin = pinyin
        self.initials = initials
    }

    func matches(_ query: SearchQuery) -> Bool {
        if Self.contains(folded, query.folded) { return true }
        guard query.isPinyinCandidate, !pinyin.isEmpty else { return false }
        return Self.contains(pinyin, query.compact) || Self.contains(initials, query.compact)
    }

    private static func contains(_ haystack: ContiguousArray<UInt8>,
                                 _ needle: ContiguousArray<UInt8>) -> Bool {
        if needle.isEmpty { return true }
        if needle.count > haystack.count { return false }
        return haystack.withUnsafeBufferPointer { h in
            needle.withUnsafeBufferPointer { n in
                memmem(h.baseAddress!, h.count, n.baseAddress!, n.count) != nil
            }
        }
    }
}

/// A query folded the same way as the index.
struct SearchQuery: Sendable {
    let folded: ContiguousArray<UInt8>
    /// The folded query without whitespace, for pinyin matching: "ni hao"
    /// and "nihao" find the same clips.
    let compact: ContiguousArray<UInt8>
    /// Pinyin only ever holds ASCII letters for Han text, so a query with
    /// anything else (Han characters, punctuation) skips those checks.
    let isPinyinCandidate: Bool

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var folded = ContiguousArray<UInt8>()
        var noPinyin = ContiguousArray<UInt8>()
        var noInitials = ContiguousArray<UInt8>()
        HanReadings.shared.transcribe(SearchFolding.foldWithoutHan(trimmed),
                                      folded: &folded,
                                      pinyin: &noPinyin,
                                      initials: &noInitials,
                                      pinyinLimit: 0)
        self.folded = folded
        self.compact = ContiguousArray(folded.filter { !SearchFolding.isASCIIWhitespace($0) })
        isPinyinCandidate = !self.compact.isEmpty
            && self.compact.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) }
    }
}

enum SearchFolding {
    /// Case, width and diacritic folding. Han characters are untouched here;
    /// HanReadings folds Traditional to Simplified while it transcribes.
    static func foldWithoutHan(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// CJK Unified Ideographs and their extensions and compatibility forms.
    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x20000...0x2A6DF, 0x2A700...0x2EBEF, 0x30000...0x3134F:
            return true
        default:
            return false
        }
    }

    static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (0x09...0x0D).contains(byte)
    }
}

/// Per-character readings and Traditional-to-Simplified forms, derived from
/// the system's ICU transforms (CFStringTransform) the first time each
/// character is seen and remembered after that, so a Han character is
/// transformed once per launch however many clips contain it.
final class HanReadings: @unchecked Sendable {
    static let shared = HanReadings()

    private static let traditionalToSimplified = StringTransform("Traditional-Simplified")

    private struct Entry {
        /// The Simplified form, or the character itself.
        let simplified: Unicode.Scalar
        /// Toneless lowercase ASCII pinyin; empty when there is no reading.
        let reading: [UInt8]
    }

    private let lock = NSLock()
    private var entries: [UInt32: Entry] = [:]

    /// Writes the folded text to `folded`, and, when it holds any Han
    /// character within the first `pinyinLimit` scalars, the pinyin and
    /// initials streams as well. All three are UTF-8.
    func transcribe(_ text: String,
                    folded: inout ContiguousArray<UInt8>,
                    pinyin: inout ContiguousArray<UInt8>,
                    initials: inout ContiguousArray<UInt8>,
                    pinyinLimit: Int) {
        folded.reserveCapacity(text.utf8.count)
        var sawHan = false
        var seen = 0
        lock.lock()
        defer { lock.unlock() }
        for scalar in text.unicodeScalars {
            let withinLimit = seen < pinyinLimit
            seen += 1
            guard SearchFolding.isHan(scalar) else {
                append(scalar, to: &folded)
                if withinLimit, !scalar.properties.isWhitespace {
                    append(scalar, to: &pinyin)
                    append(scalar, to: &initials)
                }
                continue
            }
            let entry = lockedEntry(for: scalar)
            append(entry.simplified, to: &folded)
            guard withinLimit else { continue }
            if let first = entry.reading.first {
                sawHan = true
                pinyin.append(contentsOf: entry.reading)
                initials.append(first)
            } else {
                append(entry.simplified, to: &pinyin)
                append(entry.simplified, to: &initials)
            }
        }
        if !sawHan {
            pinyin.removeAll()
            initials.removeAll()
        }
    }

    /// Toneless pinyin for one character, e.g. "zhong" for 中.
    func reading(for scalar: Unicode.Scalar) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let reading = lockedEntry(for: scalar).reading
        return reading.isEmpty ? nil : String(decoding: reading, as: UTF8.self)
    }

    private func lockedEntry(for scalar: Unicode.Scalar) -> Entry {
        if let cached = entries[scalar.value] { return cached }
        let original = String(scalar)
        let simplifiedText = original.applyingTransform(Self.traditionalToSimplified, reverse: false) ?? original
        let simplified = simplifiedText.unicodeScalars.count == 1 ? simplifiedText.unicodeScalars.first! : scalar
        let latin = String(simplified).applyingTransform(.mandarinToLatin, reverse: false) ?? ""
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        // ICU leaves a character it cannot read untouched, which this filter
        // turns into an empty reading.
        let reading = plain.lowercased().utf8.filter { (0x61...0x7A).contains($0) }
        let entry = Entry(simplified: simplified, reading: Array(reading))
        entries[scalar.value] = entry
        return entry
    }

    private func append(_ scalar: Unicode.Scalar, to bytes: inout ContiguousArray<UInt8>) {
        UTF8.encode(scalar) { bytes.append($0) }
    }
}
