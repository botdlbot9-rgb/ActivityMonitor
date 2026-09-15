#!/bin/bash
# Sign the exact tested distribution archive; never rebuild while holding the signing key.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.10.1}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
ARTIFACTS="${1:-dist}"
TOOLS=.build/artifacts/sparkle/Sparkle/bin
[[ -x "$TOOLS/generate_appcast" ]] || { echo 'Run swift package resolve first.' >&2; exit 1; }
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ARTIFACTS/ActivityMonitor-$VERSION-universal.zip" "$STAGE/"
cp .github/RELEASE_NOTES.md "$STAGE/ActivityMonitor-$VERSION-universal.md"
ARGS=(--maximum-deltas 0 --embed-release-notes --download-url-prefix "https://github.com/wieslawsoltes/ActivityMonitor/releases/download/v$VERSION/" --link 'https://github.com/wieslawsoltes/ActivityMonitor')
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
 printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/generate_appcast" --ed-key-file - "${ARGS[@]}" "$STAGE"
 # Also signs a bootstrap feed for versions predating SURequireSignedFeed.
 printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/sign_update" --ed-key-file - "$STAGE/appcast.xml"
 printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/sign_update" --ed-key-file - --verify "$STAGE/appcast.xml"
else
 "$TOOLS/generate_appcast" --account com.wieslawsoltes.ActivityMonitor "${ARGS[@]}" "$STAGE"
 "$TOOLS/sign_update" --account com.wieslawsoltes.ActivityMonitor "$STAGE/appcast.xml"
 "$TOOLS/sign_update" --account com.wieslawsoltes.ActivityMonitor --verify "$STAGE/appcast.xml"
fi
# Independently verify the archive against the public key shipped in the application.
python3 scripts/verify-appcast.py "$STAGE/appcast.xml" "$ARTIFACTS/ActivityMonitor-$VERSION-universal.zip" "$VERSION"
cp "$STAGE/appcast.xml" "$ARTIFACTS/appcast.xml"
