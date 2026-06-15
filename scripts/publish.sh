#!/usr/bin/env bash
#
# Publish a new version of Aurora (Production / Release):
#   1. Bumps MARKETING_VERSION in project.pbxproj    (patch by default).
#   2. Archives the Release configuration of Aurora.
#   3. Code-signs the .app  (adhoc — Self-signed, no Developer ID needed yet).
#   4. Packages it into a .dmg.
#   5. Signs the .dmg with the Sparkle EdDSA private key (stored in Keychain).
#   6. Prepends a new <item> to releases/appcast.xml so the Production app's
#      Sparkle updater can see the new version.
#
# Usage:
#   scripts/publish.sh                  # bump patch  (e.g. 1.0.0 → 1.0.1)
#   scripts/publish.sh --minor          # bump minor  (e.g. 1.0.4 → 1.1.0)
#   scripts/publish.sh --major          # bump major  (e.g. 1.4.2 → 2.0.0)
#
# Environment overrides:
#   RELEASE_BASE_URL  — base URL the appcast points to. Defaults to
#                       file://<project>/releases (local). Phase 4 will set
#                       it to the GitHub Releases URL.
#   APPCAST_TITLE     — defaults to "Aurora".
#   PROJECT_NAME      — defaults to "Aurora" (the PRODUCT_NAME of the
#                       Release configuration; must match Aurora.app).

set -euo pipefail

# -------- Config --------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT_FILE="commanderonev2.xcodeproj"
SCHEME="commanderonev2"
PRODUCT_NAME="${PRODUCT_NAME:-Aurora}"
RELEASES_DIR="$PROJECT_DIR/releases"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/${PRODUCT_NAME}.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APPCAST="$RELEASES_DIR/appcast.xml"
APPCAST_TITLE="${APPCAST_TITLE:-Aurora}"
RELEASE_BASE_URL_DEFAULT="file://$RELEASES_DIR"
RELEASE_BASE_URL="${RELEASE_BASE_URL:-$RELEASE_BASE_URL_DEFAULT}"

mkdir -p "$RELEASES_DIR" "$BUILD_DIR"

# -------- Arg parsing ---------------------------------------------------------
BUMP_KIND="patch"
case "${1:-}" in
    --minor) BUMP_KIND="minor" ;;
    --major) BUMP_KIND="major" ;;
    --patch|"") BUMP_KIND="patch" ;;
    *) echo "Unknown flag: $1 (use --patch | --minor | --major)" >&2; exit 1 ;;
esac

# -------- 1. Read and bump version -------------------------------------------
CURRENT_VERSION="$(grep -m1 "MARKETING_VERSION = " "$PROJECT_FILE/project.pbxproj" \
                     | sed -E 's/.*MARKETING_VERSION = ([0-9.]+);.*/\1/')"
if [[ ! "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "ERROR: Could not parse current MARKETING_VERSION: '$CURRENT_VERSION'" >&2
    exit 1
fi

# Normalise to MAJOR.MINOR.PATCH (Xcode allows 1.0)
IFS='.' read -r CV_MAJOR CV_MINOR CV_PATCH <<<"$CURRENT_VERSION"
CV_PATCH="${CV_PATCH:-0}"

case "$BUMP_KIND" in
    patch) NEW_MAJOR=$CV_MAJOR; NEW_MINOR=$CV_MINOR; NEW_PATCH=$((CV_PATCH + 1)) ;;
    minor) NEW_MAJOR=$CV_MAJOR; NEW_MINOR=$((CV_MINOR + 1)); NEW_PATCH=0 ;;
    major) NEW_MAJOR=$((CV_MAJOR + 1)); NEW_MINOR=0; NEW_PATCH=0 ;;
esac
NEW_VERSION="$NEW_MAJOR.$NEW_MINOR.$NEW_PATCH"

echo "Publishing Aurora $CURRENT_VERSION → $NEW_VERSION"
echo

# Write back into both Debug and Release configs in the pbxproj.
# Match the exact "MARKETING_VERSION = <ver>;" line to avoid clobbering numbers
# that look similar elsewhere.
/usr/bin/sed -i '' "s/MARKETING_VERSION = $CURRENT_VERSION;/MARKETING_VERSION = $NEW_VERSION;/g" \
    "$PROJECT_FILE/project.pbxproj"

# Sanity: the change actually happened.
if ! grep -q "MARKETING_VERSION = $NEW_VERSION;" "$PROJECT_FILE/project.pbxproj"; then
    echo "ERROR: MARKETING_VERSION did not update — aborting." >&2
    exit 1
fi

# -------- 2. Archive the Release configuration -------------------------------
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
echo "Archiving Release config…"
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -quiet \
    archive

APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/${PRODUCT_NAME}.app"
if [[ ! -d "$APP_IN_ARCHIVE" ]]; then
    echo "ERROR: Archive did not produce '$APP_IN_ARCHIVE'." >&2
    echo "Tip: PRODUCT_NAME in the Release config is '$PRODUCT_NAME' — must match." >&2
    exit 1
fi

# -------- 3. Copy + adhoc code sign -----------------------------------------
mkdir -p "$EXPORT_DIR"
cp -R "$APP_IN_ARCHIVE" "$EXPORT_DIR/"
APP_PATH="$EXPORT_DIR/${PRODUCT_NAME}.app"

echo "Adhoc signing…"
codesign --force --deep --sign - "$APP_PATH"

# -------- 4. Build the DMG ---------------------------------------------------
DMG_NAME="${PRODUCT_NAME}-${NEW_VERSION}.dmg"
DMG_PATH="$RELEASES_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

echo "Building DMG → $DMG_NAME"
hdiutil create \
    -volname "${PRODUCT_NAME} ${NEW_VERSION}" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    -quiet \
    "$DMG_PATH"

DMG_SIZE_BYTES=$(stat -f%z "$DMG_PATH")

# -------- 5. Sign the DMG with Sparkle ---------------------------------------
find_sparkle_tool() {
    find "$HOME/Library/Developer/Xcode/DerivedData" \
        -name "$1" -path "*Sparkle*/bin/*" -type f 2>/dev/null | head -1
}

SIGN_UPDATE="$(find_sparkle_tool sign_update)"
if [[ -z "$SIGN_UPDATE" ]]; then
    echo "ERROR: Sparkle's sign_update tool not found." >&2
    echo "Add Sparkle in Xcode and build once, then re-run." >&2
    exit 1
fi

SIGN_OUTPUT="$("$SIGN_UPDATE" "$DMG_PATH")"
# sign_update prints e.g.: sparkle:edSignature="…" length="…"
ED_SIG="$(echo "$SIGN_OUTPUT" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')"
ENCLOSURE_LEN="$(echo "$SIGN_OUTPUT" | sed -nE 's/.*length="([^"]+)".*/\1/p')"
ENCLOSURE_LEN="${ENCLOSURE_LEN:-$DMG_SIZE_BYTES}"

if [[ -z "$ED_SIG" ]]; then
    echo "ERROR: Could not extract Sparkle signature from sign_update output:" >&2
    echo "$SIGN_OUTPUT" >&2
    exit 1
fi

# -------- 6. Update the appcast.xml ------------------------------------------
NOW_RFC822="$(LC_ALL=C TZ=UTC date "+%a, %d %b %Y %H:%M:%S +0000")"
NEW_ITEM_XML="    <item>
      <title>Version $NEW_VERSION</title>
      <pubDate>$NOW_RFC822</pubDate>
      <enclosure
        url=\"$RELEASE_BASE_URL/$DMG_NAME\"
        sparkle:version=\"$NEW_VERSION\"
        sparkle:shortVersionString=\"$NEW_VERSION\"
        sparkle:edSignature=\"$ED_SIG\"
        length=\"$ENCLOSURE_LEN\"
        type=\"application/octet-stream\" />
    </item>"

if [[ ! -f "$APPCAST" ]]; then
    cat >"$APPCAST" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APPCAST_TITLE</title>
$NEW_ITEM_XML
  </channel>
</rss>
EOF
else
    # Prepend the new <item> right after <channel><title>…</title>.
    TMP_APPCAST="$(mktemp)"
    awk -v insert="$NEW_ITEM_XML" '
        /<\/title>/ && !done {
            print
            print insert
            done=1
            next
        }
        { print }
    ' "$APPCAST" >"$TMP_APPCAST"
    mv "$TMP_APPCAST" "$APPCAST"
fi

# -------- Done ---------------------------------------------------------------
cat <<EOF

✅ Published Aurora $NEW_VERSION

   DMG       : $DMG_PATH         ($((DMG_SIZE_BYTES / 1024 / 1024)) MB)
   Appcast   : $APPCAST
   Feed URL  : $RELEASE_BASE_URL/appcast.xml

Next steps (Phase 4):
  • Upload "$DMG_NAME" and appcast.xml to GitHub Releases (or your CDN).
  • Set SUFeedURL in commanderonev2/Info.plist to the final URL.
  • Open the Production app → menu Aurora > Check for Updates… should
    show "$NEW_VERSION available — Update Now".
EOF
