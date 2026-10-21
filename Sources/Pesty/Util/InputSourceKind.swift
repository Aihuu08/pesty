import Carbon.HIToolbox

/// Whether keystrokes currently go through an input method (Pinyin, Wubi,
/// Zhuyin, Japanese Kana and so on) or map straight to characters through a
/// plain keyboard layout.
enum InputSourceKind: Equatable {
    case keyboardLayout
    case inputMethod

    /// Classifies a Text Input Sources type identifier
    /// (kTISPropertyInputSourceType). Anything that is not a plain keyboard
    /// layout is treated as an input method, which is the safe side: it
    /// never has raw key characters typed past it.
    init(typeID: String) {
        self = typeID == (kTISTypeKeyboardLayout as String) ? .keyboardLayout : .inputMethod
    }

    @MainActor
    static var current: InputSourceKind {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else {
            return .keyboardLayout
        }
        let typeID = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        return InputSourceKind(typeID: typeID)
    }
}
