#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
APP="packaging/Pesty.app"

echo "==> Building universal release binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Pesty"
echo "    binary: $BIN"

echo "==> Generating icon"
bash scripts/make_icon.sh >/dev/null

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pesty"
cp packaging/Pesty.icns "$APP/Contents/Resources/Pesty.icns"

# SwiftUI's Text("…") and String(localized:) look the strings up in the main
# bundle, so the catalog is compiled straight into Contents/Resources as
# en.lproj and zh-Hans.lproj rather than into a SwiftPM resource bundle.
echo "==> Compiling localizations"
xcrun xcstringstool compile --output-directory "$APP/Contents/Resources" packaging/Localizable.xcstrings
for lang in en zh-Hans; do
  if [ ! -d "$APP/Contents/Resources/$lang.lproj" ]; then
    echo "error: $lang.lproj was not produced from packaging/Localizable.xcstrings" >&2
    exit 1
  fi
done

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    packaging/Info.plist > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Explicitly sign the assembled bundle with a stable designated requirement.
# Without this, each release build only carries Swift's per-binary linker
# signature (a changing CDHash), which makes macOS ask for Accessibility again.
#
# SIGN_IDENTITY names a code-signing certificate in your login keychain (a
# self-signed one is enough, see docs/selfuse/HANDOFF.md). The requirement then
# also pins that certificate, so another program cannot satisfy it, and inherit
# Pesty's Accessibility grant, just by reusing the bundle identifier. Without it
# the bundle is signed ad hoc, which pins the identifier only.
if [ -n "${SIGN_IDENTITY:-}" ]; then
  CERT_SHA1="$(security find-certificate -c "$SIGN_IDENTITY" -Z 2>/dev/null \
    | awk '/SHA-1 hash:/ { print $3; exit }')"
  if [ -z "$CERT_SHA1" ]; then
    echo "error: no certificate named \"$SIGN_IDENTITY\" in the keychain" >&2
    exit 1
  fi
  echo "==> Signing $APP with \"$SIGN_IDENTITY\" ($CERT_SHA1)"
  /usr/bin/codesign --force --sign "$CERT_SHA1" --identifier com.greycorelabs.pesty \
    -r="designated => identifier \"com.greycorelabs.pesty\" and certificate leaf = H\"$CERT_SHA1\"" "$APP"
else
  echo "==> Signing $APP ad hoc (set SIGN_IDENTITY to pin a certificate)"
  /usr/bin/codesign --force --sign - --identifier com.greycorelabs.pesty \
    -r='designated => identifier "com.greycorelabs.pesty"' "$APP"
fi

echo "==> Built $APP"
/usr/bin/file "$APP/Contents/MacOS/Pesty"
echo "    version $VERSION ($BUILD)"
