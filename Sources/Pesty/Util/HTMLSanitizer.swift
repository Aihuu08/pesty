import Foundation

/// Rewrites captured HTML so the system HTML importer has nothing to fetch.
///
/// NSAttributedString's HTML import runs WebKit, which requests the images,
/// stylesheets and frames a document references (a test against a loopback
/// listener saw seven requests from one clip). A clip copied from a web page
/// would otherwise make "Paste with Clean Formatting" or "Paste as Markdown"
/// contact whatever servers the page pointed at, tracking pixels included.
///
/// The document is parsed (no external entities), then rebuilt from an
/// allowlist: text and formatting elements survive, anything that embeds or
/// loads something is removed with its contents, and only attributes that
/// cannot carry a resource reference are kept. Returns nil when the HTML
/// cannot be parsed; callers then fall back to RTF or plain text.
enum HTMLSanitizer {
    static func sanitized(_ html: Data) -> Data? {
        // Parsed from a String we decoded, not from bytes: given bytes, the
        // tidy parser read UTF-8 as Latin-1 and turned Chinese into mojibake.
        guard let text = decoded(html),
              let document = try? XMLDocument(xmlString: withoutPrologue(text),
                                              options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return nil }
        document.dtd = nil
        cleanAttributes(of: root)
        clean(root)
        let body = root.elements(forName: "body").first ?? root
        let markup = (body.children ?? []).map { $0.xmlString }.joined()
        // Our own charset declaration: the original <meta> went with <head>.
        return Data(("<html><head><meta charset=\"utf-8\"></head><body>" + markup + "</body></html>").utf8)
    }

    /// Pasteboard HTML is UTF-8 in practice; UTF-16 (with a byte order mark)
    /// also turns up. Anything else is not worth guessing at.
    private static func decoded(_ html: Data) -> String? {
        if html.starts(with: [0xFF, 0xFE]) || html.starts(with: [0xFE, 0xFF]) {
            return String(data: html, encoding: .utf16)
        }
        return String(data: html, encoding: .utf8)
    }

    /// A doctype naming an external DTD, XML declarations and comments carry
    /// no formatting and can make the tidy parser give up; drop them first.
    private static func withoutPrologue(_ html: String) -> String {
        var text = html
        for pattern in ["<!DOCTYPE[^>]*>", "<\\?xml[^>]*\\?>", "<!--[\\s\\S]*?-->"] {
            text = text.replacingOccurrences(of: pattern, with: "",
                                             options: [.regularExpression, .caseInsensitive])
        }
        return text
    }

    /// Removed together with everything inside them.
    private static let droppedElements: Set<String> = [
        "head", "script", "noscript", "style", "link", "meta", "base", "title", "template",
        "img", "image", "picture", "source", "track", "video", "audio", "canvas", "map", "area",
        "iframe", "frame", "frameset", "object", "embed", "applet", "param", "portal",
        "svg", "math", "form", "input", "button", "select", "option", "textarea",
        "dialog", "slot"
    ]

    private static let keptAttributes: Set<String> = [
        "href", "style", "colspan", "rowspan", "align", "dir", "lang", "title"
    ]

    private static func clean(_ element: XMLElement) {
        for child in element.children ?? [] {
            switch child.kind {
            case .element:
                guard let child = child as? XMLElement else { continue }
                let name = (child.localName ?? child.name ?? "").lowercased()
                if droppedElements.contains(name) {
                    child.detach()
                    continue
                }
                cleanAttributes(of: child)
                clean(child)
            case .text:
                continue
            default:
                // Comments, processing instructions, DTD nodes.
                child.detach()
            }
        }
    }

    private static func cleanAttributes(of element: XMLElement) {
        let elementName = (element.localName ?? element.name ?? "").lowercased()
        for attribute in element.attributes ?? [] {
            guard let rawName = attribute.name else { continue }
            let name = rawName.lowercased()
            let value = attribute.stringValue ?? ""
            let keep: Bool
            switch name {
            case "href":
                // Followed only when the reader clicks it, never fetched by
                // the importer; anchors keep web and mail links.
                keep = elementName == "a" && isWebOrMailLink(value)
            case "style":
                keep = !mayReferenceResource(value)
            default:
                keep = keptAttributes.contains(name)
            }
            if !keep { element.removeAttribute(forName: rawName) }
        }
    }

    private static func isWebOrMailLink(_ value: String) -> Bool {
        let scheme = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.lowercased()
        return ["http", "https", "mailto"].contains(scheme ?? "")
    }

    /// Any inline CSS that could name something to load. Backslashes are
    /// refused outright because CSS escapes can spell "url" in disguise.
    private static func mayReferenceResource(_ css: String) -> Bool {
        let compact = css.lowercased().filter { !$0.isWhitespace }
        return compact.contains("url(") || compact.contains("image(") || compact.contains("image-set(")
            || compact.contains("@import") || compact.contains("expression(") || compact.contains("src(")
            || compact.contains("\\")
    }
}
