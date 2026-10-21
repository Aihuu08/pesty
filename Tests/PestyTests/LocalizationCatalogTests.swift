import XCTest

/// Guards packaging/Localizable.xcstrings, which build_app.sh compiles into
/// the app. Coverage against the sources is checked by
/// scripts/dev/extract_l10n_keys.py --check.
final class LocalizationCatalogTests: XCTestCase {
    private func catalog() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("packaging/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual(json?["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(json?["strings"] as? [String: [String: Any]])
    }

    private func values(of localization: Any?) -> [String] {
        guard let dict = localization as? [String: Any] else { return [] }
        if let unit = dict["stringUnit"] as? [String: Any], let value = unit["value"] as? String { return [value] }
        if let variations = dict["variations"] as? [String: Any] {
            return variations.values.flatMap { kind -> [String] in
                (kind as? [String: Any])?.values.flatMap { values(of: $0) } ?? []
            }
        }
        return []
    }

    private func specifiers(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(lld|@)")
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) }
    }

    func testEveryKeyHasASimplifiedChineseTranslation() throws {
        for (key, entry) in try catalog() {
            let zh = values(of: (entry["localizations"] as? [String: Any])?["zh-Hans"])
            XCTAssertFalse(zh.isEmpty, "no zh-Hans for \(key)")
            XCTAssertFalse(zh.contains(where: \.isEmpty), "empty zh-Hans for \(key)")
        }
    }

    func testTranslationsKeepTheKeysFormatSpecifiers() throws {
        for (key, entry) in try catalog() {
            let expected = specifiers(key)
            for (lang, loc) in (entry["localizations"] as? [String: Any]) ?? [:] {
                for value in values(of: loc) {
                    XCTAssertEqual(specifiers(value), expected, "\(lang) for \(key): \(value)")
                }
            }
        }
    }
}
