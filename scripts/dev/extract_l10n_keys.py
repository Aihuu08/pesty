#!/usr/bin/env python3
"""Lists the localization keys the Swift sources use, as String Catalog keys.

There is no Xcode project to extract them automatically, so this scans for
the call sites that localize: String(localized: "...") and SwiftUI views and
modifiers whose string-literal argument is a LocalizedStringKey. Interpolated
values become format specifiers the way the Swift compiler writes them
(%lld for integers, %@ for strings). An interpolation it cannot classify is
reported so the table below can be extended.

Usage:
  scripts/dev/extract_l10n_keys.py            print every key
  scripts/dev/extract_l10n_keys.py --check    exit 1 if a key is missing from
                                              packaging/Localizable.xcstrings
                                              or lacks a zh-Hans translation
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = ROOT / "Sources" / "Pesty"
CATALOG = ROOT / "packaging" / "Localizable.xcstrings"

INTEGER = {
    "count", "targets.count", "draftLimit", "pendingRemovalCount", "item.fileURLs.count",
    "item.charCount", "characters", "words", "lines", "Int(settings.barHeight)", "index + 1",
}
OBJECT = {
    "name", "item.displayTitle", "item.type.label", "Bundle.main.appVersion",
    "Settings.shared.hotkeyDisplay", "store.searchText", "applicationName(for: bundleID)",
    "modifier.symbol", "modifier.title",
}

# Call sites whose first string literal is localized.
SWIFTUI = r'(?<![A-Za-z])(?:Text|Label|Button|Toggle|Section|Picker|LabeledContent|Link|ColorPicker|ContentUnavailableView|Menu|unavailable|\.help|\.accessibilityLabel|\.alert)'
PATTERNS = [
    re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(SWIFTUI + r'\(\s*"((?:[^"\\]|\\.)*)"'),
    # Ternaries of literals inside Text(...) and .help(...)
    re.compile(r'(?:Text|\.help)\([^()\n]*\?\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'(?:Text|\.help)\([^()\n]*\?\s*"(?:[^"\\]|\\.)*"\s*:\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'^\s*:\s*"((?:[^"\\]|\\.)*)"\)', re.M),
    re.compile(r'^\s*\?\s*"((?:[^"\\]|\\.)*)"\s*$', re.M),
    re.compile(r'^\s*:\s*\(requestedGrant\s*$', re.M),
]
# Literals that are not user-facing words; never need a translation.
IGNORED = {"%@ %@", "%lld", "", "+ 1…9", "Pesty", "GitHub"}


def interpolation_to_specifier(match, unknown):
    expr = match.group(1)
    if expr in INTEGER:
        return "%lld"
    if expr in OBJECT:
        return "%@"
    unknown.add(expr)
    return "%@"


def keys():
    found, unknown = {}, set()
    for path in sorted(SOURCES.rglob("*.swift")):
        text = path.read_text()
        # MAS-only code is not built here; skip its strings.
        text = re.sub(r'#if MAS\n.*?(#else|#endif)', r'\1', text, flags=re.S)
        for pattern in PATTERNS:
            for m in pattern.finditer(text):
                if not m.groups():
                    continue
                raw = m.group(1)
                key = re.sub(r'\\\(([^()]*(?:\([^()]*\))?[^()]*)\)',
                             lambda mm: interpolation_to_specifier(mm, unknown), raw)
                key = key.replace('\\u{2019}', '’').replace('\\n', '\n').replace('\\"', '"')
                if key in IGNORED or not re.search(r'[A-Za-z]', key):
                    continue
                found.setdefault(key, f"{path.relative_to(ROOT)}")
    return found, unknown


def main():
    found, unknown = keys()
    if unknown:
        print("Unclassified interpolations (add to INTEGER or OBJECT):", sorted(unknown))
    if "--check" not in sys.argv:
        for key, where in sorted(found.items()):
            print(f"{where}: {json.dumps(key, ensure_ascii=False)}")
        return 0
    catalog = json.loads(CATALOG.read_text())["strings"]
    missing = [k for k in found if k not in catalog]
    untranslated = [k for k, v in catalog.items()
                    if "zh-Hans" not in v.get("localizations", {}) and not v.get("shouldTranslate") is False]
    unused = [k for k in catalog if k not in found]
    for k in sorted(missing):
        print("MISSING     ", json.dumps(k, ensure_ascii=False), "from", found[k])
    for k in sorted(untranslated):
        print("UNTRANSLATED", json.dumps(k, ensure_ascii=False))
    for k in sorted(unused):
        print("UNUSED      ", json.dumps(k, ensure_ascii=False))
    ok = not missing and not untranslated and not unknown
    print(f"{len(found)} keys in sources, {len(catalog)} in catalog:", "OK" if ok else "PROBLEMS")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
