#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
app='build/macos/Build/Products/Release/SKCPL - Connect to Waves.app'
[[ -d "$app" ]] || { echo 'macOS release .app is missing.' >&2; exit 1; }
# Reject an accidentally ARM-only package when advertising both Mac families.
for binary in "$app/Contents/MacOS/SKCPL - Connect to Waves" "$app/Contents/Frameworks/App.framework/Versions/A/App"; do
  lipo "$binary" -verify_arch arm64 x86_64
done
mkdir -p dist
export MACOS_SIGNED=false MACOS_NOTARIZED=false
if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  while IFS= read -r -d '' item; do
    codesign --force --timestamp --options runtime --sign "$APPLE_SIGNING_IDENTITY" "$item"
  done < <(find "$app/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
  codesign --force --timestamp --options runtime --entitlements macos/Runner/Release.entitlements --sign "$APPLE_SIGNING_IDENTITY" "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
  export MACOS_SIGNED=true
fi
archive="$PWD/dist/SKCPL-macOS.zip"
rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if [[ -n "${APPLE_NOTARY_PRIVATE_KEY_BASE64:-}" ]]; then
  [[ "$MACOS_SIGNED" == true ]] || { echo 'Notarization requires a Developer ID signature.' >&2; exit 1; }
  : "${APPLE_NOTARY_KEY_ID:?Missing notary key ID}"
  : "${APPLE_NOTARY_ISSUER:?Missing notary issuer}"
  key="$(mktemp -t skcpl-notary).p8"
  trap 'rm -f "$key"' EXIT
  printf '%s' "$APPLE_NOTARY_PRIVATE_KEY_BASE64" | base64 --decode > "$key"
  chmod 600 "$key"
  xcrun notarytool submit "$archive" --key "$key" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
  rm "$archive"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
  export MACOS_NOTARIZED=true
fi
if [[ "$MACOS_NOTARIZED" != true ]]; then
  echo '::warning::macOS ZIP is not notarized. Apple Gatekeeper may block downloaded copies. Configure Apple signing/notary secrets for a trusted public release.'
fi
python3 scripts/release_manifest.py --platform macos-universal --artifact "$archive"
