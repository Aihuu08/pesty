import Foundation

/// The cheap-to-compare parts of a clip that feed its search text. A cached
/// index is reused while these match; edits that keep the same text length
/// invalidate the cache explicitly (ClipboardStore.updateContent).
struct ClipSearchSignature: Equatable, Sendable {
    let textBytes: Int
    let customTitle: String?
    let sourceAppName: String?
    let colorHex: String?
    let fileURLs: [String]

    init(_ item: ClipItem) {
        textBytes = item.text?.utf8.count ?? -1
        customTitle = item.customTitle
        sourceAppName = item.sourceAppName
        colorHex = item.colorHex
        fileURLs = item.fileURLs
    }
}

struct CachedSearchIndex: Sendable {
    let signature: ClipSearchSignature
    let index: SearchIndex
}
