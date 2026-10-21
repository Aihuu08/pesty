import XCTest
@testable import Pesty

/// Finding B of the security review: does converting an HTML clip for
/// "Paste with Clean Formatting" / "Paste as Markdown" fetch the remote
/// resources the HTML references? A listener on 127.0.0.1 (loopback only,
/// test code only) stands in for a remote server; a connection to it means
/// the importer reached out.
final class HTMLImportNetworkTests: XCTestCase {
    func testHTMLConversionDoesNotFetchReferencedResources() throws {
        let listener = try LoopbackListener()
        defer { listener.close() }
        let base = "http://127.0.0.1:\(listener.port)"
        let html = """
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "\(base)/dtd">
        <html manifest="\(base)/manifest"><head>
        <link rel="stylesheet" href="\(base)/style.css">
        <link rel="icon" href="\(base)/favicon.ico">
        <base href="\(base)/">
        <script src="\(base)/script.js"></script>
        <style>@import url("\(base)/import.css"); body { background: url("\(base)/bg.png"); }</style>
        </head><body background="\(base)/body.png">
        <p><b>Bold</b> and <a href="\(base)/link">a link</a>.</p>
        <p style="background-image: url('\(base)/inline.png')">styled</p>
        <p style="background: u\\72l(\(base)/escaped.png)">escaped</p>
        <img src="\(base)/pixel.png" width="1" height="1">
        <img srcset="\(base)/srcset.png 2x">
        <picture><source srcset="\(base)/source.png"></picture>
        <table background="\(base)/table.png"><tr><td background="\(base)/td.png">cell</td></tr></table>
        <input type="image" src="\(base)/input.png">
        <video poster="\(base)/poster.png" src="\(base)/video.mp4"></video>
        <object data="\(base)/object.bin"></object>
        <embed src="\(base)/embed.bin">
        <svg><image href="\(base)/svg.png"/></svg>
        <iframe src="\(base)/frame.html"></iframe>
        </body></html>
        """
        let item = ClipItem(type: .text, text: "Bold and a link.", htmlData: Data(html.utf8))

        let markdown = FormatConverter.markdown(for: item)
        print("HTML-MARKDOWN", markdown ?? "nil")
        _ = FormatConverter.cleanedRTF(for: item)
        // The formatting itself still comes through.
        XCTAssertTrue(markdown?.contains("**Bold**") == true, markdown ?? "nil")
        XCTAssertTrue(markdown?.contains("](\(base)/link)") == true, markdown ?? "nil")

        let deadline = Date().addingTimeInterval(3)
        var connections = 0
        while Date() < deadline {
            connections += listener.acceptPending()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        print("HTML-IMPORT-NETWORK connections=\(connections)")
        XCTAssertEqual(connections, 0, "the HTML importer requested a resource referenced by the clip")
    }
}

/// A non-blocking TCP listener on 127.0.0.1 with an OS-assigned port.
private final class LoopbackListener {
    private let fd: Int32
    let port: UInt16

    init() throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw POSIXError(.EIO) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(sock, 16) == 0 else { Darwin.close(sock); throw POSIXError(.EADDRINUSE) }
        _ = fcntl(sock, F_SETFL, fcntl(sock, F_GETFL) | O_NONBLOCK)
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &length) }
        }
        fd = sock
        port = UInt16(bigEndian: actual.sin_port)
    }

    /// Accepts and closes whatever connections are waiting; returns how many.
    func acceptPending() -> Int {
        var count = 0
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { return count }
            Darwin.close(client)
            count += 1
        }
    }

    func close() { Darwin.close(fd) }
}

final class HTMLSanitizerTests: XCTestCase {
    private func clean(_ html: String) -> String {
        String(decoding: HTMLSanitizer.sanitized(Data(html.utf8)) ?? Data(), as: UTF8.self)
    }

    func testKeepsFormattingAndLinks() {
        let out = clean("<p><b>bold</b> <i>it</i> <a href=\"https://example.com\">x</a></p>")
        XCTAssertTrue(out.contains("<b>bold</b>"), out)
        XCTAssertTrue(out.contains("<i>it</i>"), out)
        XCTAssertTrue(out.contains("href=\"https://example.com\""), out)
    }

    func testRemovesEverythingThatLoads() {
        let out = clean("""
        <img src="http://h/a.png"><p style="background:url(http://h/b.png)">t</p>
        <a href="javascript:alert(1)">j</a><table background="http://h/c.png"><tr><td>c</td></tr></table>
        """).lowercased()
        for needle in ["<img", "url(", "javascript:", "background=", "http://h/"] {
            XCTAssertFalse(out.contains(needle), "\(needle) survived: \(out)")
        }
        XCTAssertTrue(out.contains("<p>t"), out)
        XCTAssertTrue(out.contains("<td>c"), out)
    }

    func testSanitizedChineseHTMLStillConverts() {
        let item = ClipItem(type: .text, text: "粗体 链接",
                            htmlData: Data("<meta charset='utf-8'><b>粗体</b> <a href=\"https://example.com\">链接</a>".utf8))
        let markdown = FormatConverter.markdown(for: item) ?? "nil"
        XCTAssertTrue(markdown.hasPrefix("**粗体** [链接](https://example.com"), markdown)
    }

    func testKeepsHarmlessInlineStyles() {
        let out = clean("<p><span style=\"font-weight:700\">heavy</span></p>")
        XCTAssertTrue(out.contains("font-weight:700"), out)
    }
}

