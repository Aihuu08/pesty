import XCTest
@testable import Pesty

final class SearchIndexTests: XCTestCase {
    private func matches(_ text: String, _ query: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let q = SearchQuery(query) else {
            XCTFail("empty query", file: file, line: line)
            return false
        }
        return SearchIndex(text: text).matches(q)
    }

    func testFoldsCaseWidthAndDiacritics() {
        XCTAssertTrue(matches("Hello World", "hello"))
        XCTAssertTrue(matches("ＡＢＣ１２３", "abc123"))
        XCTAssertTrue(matches("abc123", "ＡＢＣ"))
        XCTAssertTrue(matches("Café résumé", "cafe resume"))
        XCTAssertFalse(matches("Hello World", "planet"))
    }

    func testFindsHanByFullPinyinAndInitials() {
        XCTAssertTrue(matches("你好世界", "nihao"))
        XCTAssertTrue(matches("你好世界", "ni hao"))
        XCTAssertTrue(matches("你好世界", "shijie"))
        XCTAssertTrue(matches("你好世界", "nhsj"))
        XCTAssertTrue(matches("你好世界", "NIHAO"))
        XCTAssertTrue(matches("微信 WeChat", "wx"))
        XCTAssertTrue(matches("微信 WeChat", "weixin"))
        XCTAssertTrue(matches("微信 WeChat", "wechat"))
        XCTAssertFalse(matches("你好世界", "hello"))
    }

    func testPinyinIsOnlyUsedForTextWithHan() {
        XCTAssertFalse(matches("plain english text", "pet"))
        XCTAssertTrue(matches("plain english text", "english"))
    }

    func testTraditionalAndSimplifiedFindEachOther() {
        XCTAssertTrue(matches("這是繁體中文", "这是繁体"))
        XCTAssertTrue(matches("这是简体中文", "這是簡體"))
        XCTAssertTrue(matches("這是繁體", "zheshi"))
    }

    /// Documents the known limit: one default reading per character.
    func testPolyphonicCharactersUseTheirDefaultReading() {
        XCTAssertEqual(HanReadings.shared.reading(for: "中" as Unicode.Scalar), "zhong")
        XCTAssertTrue(matches("重庆", "zhongqing"))
    }

    func testHanQueryMatchesHanTextDirectly() {
        XCTAssertTrue(matches("今天天气不错", "天气"))
        XCTAssertFalse(matches("今天天气不错", "下雨"))
    }

    func testBlankQueryIsNoQuery() {
        XCTAssertNil(SearchQuery("   "))
        XCTAssertNil(SearchQuery(""))
    }

    func testPercentEncodedFilePathsAreSearchable() {
        let item = ClipItem(type: .file, text: "报告.pdf",
                            fileURLs: ["file:///Users/me/%E6%96%87%E6%A1%A3/%E6%8A%A5%E5%91%8A.pdf"])
        let index = SearchIndex(text: item.searchSource)
        XCTAssertTrue(index.matches(SearchQuery("文档")!))
        XCTAssertTrue(index.matches(SearchQuery("wendang")!))
    }

    func testSignatureNoticesTitleAndLengthChanges() {
        var item = ClipItem(type: .text, text: "abc")
        let before = ClipSearchSignature(item)
        item.customTitle = "x"
        XCTAssertNotEqual(before, ClipSearchSignature(item))
        item.customTitle = nil
        item.text = "abcd"
        XCTAssertNotEqual(before, ClipSearchSignature(item))
    }
}

final class InputSourceKindTests: XCTestCase {
    func testOnlyPlainKeyboardLayoutsCountAsLayouts() {
        XCTAssertEqual(InputSourceKind(typeID: "TISTypeKeyboardLayout"), .keyboardLayout)
        XCTAssertEqual(InputSourceKind(typeID: "TISTypeKeyboardInputMode"), .inputMethod)
        XCTAssertEqual(InputSourceKind(typeID: "TISTypeKeyboardInputMethodModeEnabled"), .inputMethod)
        XCTAssertEqual(InputSourceKind(typeID: "anything else"), .inputMethod)
    }
}
