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
        <html><head>
        <link rel="stylesheet" href="\(base)/style.css">
        <style>@import url("\(base)/import.css"); body { background: url("\(base)/bg.png"); }</style>
        </head><body>
        <p><b>Bold</b> and <a href="\(base)/link">a link</a>.</p>
        <img src="\(base)/pixel.png" width="1" height="1">
        <iframe src="\(base)/frame.html"></iframe>
        </body></html>
        """
        let item = ClipItem(type: .text, text: "Bold and a link.", htmlData: Data(html.utf8))

        _ = FormatConverter.markdown(for: item)
        _ = FormatConverter.cleanedRTF(for: item)

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
