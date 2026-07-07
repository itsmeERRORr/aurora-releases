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
#   7. (If `gh` CLI is installed and authenticated) creates the GitHub Release
#      and uploads the DMG and updated appcast.xml as assets — the Production
#      app's Sparkle picks them up automatically.
#
# Usage:
#   scripts/publish.sh                  # bump patch  (e.g. 1.0.0 → 1.0.1)
#   scripts/publish.sh --minor          # bump minor  (e.g. 1.0.4 → 1.1.0)
#   scripts/publish.sh --major          # bump major  (e.g. 1.4.2 → 2.0.0)
#   scripts/publish.sh --local-only     # skip GitHub upload (Phase-3 behaviour)
#
# Environment overrides:
#   GITHUB_OWNER      — GitHub user/org that owns the releases repo. Defaults
#                       to whatever `gh api user --jq .login` returns.
#   GITHUB_REPO       — Releases repository name. Defaults to "aurora-releases".
#   RELEASE_BASE_URL  — Base URL embedded in the appcast's <enclosure url=...>.
#                       Auto-derived from GITHUB_OWNER/REPO/version unless set.
#   APPCAST_TITLE     — Defaults to "Aurora".
#   PROJECT_NAME      — Defaults to "Aurora" (the PRODUCT_NAME of the Release
#                       configuration; must match Aurora.app).

set -euo pipefail

# -------- Config --------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-aurora}"
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

mkdir -p "$RELEASES_DIR" "$BUILD_DIR"

# -------- GitHub Releases setup ----------------------------------------------
GITHUB_REPO="${GITHUB_REPO:-aurora-releases}"
LOCAL_ONLY=0
USE_GITHUB=1

resolve_github_owner() {
    if [[ -n "${GITHUB_OWNER:-}" ]]; then
        printf '%s' "$GITHUB_OWNER"
        return 0
    fi
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh api user --jq .login 2>/dev/null
    fi
}

# -------- Arg parsing ---------------------------------------------------------
BUMP_KIND="patch"
for arg in "$@"; do
    case "$arg" in
        --minor) BUMP_KIND="minor" ;;
        --major) BUMP_KIND="major" ;;
        --patch) BUMP_KIND="patch" ;;
        --local-only) LOCAL_ONLY=1; USE_GITHUB=0 ;;
        "") : ;;
        *) echo "Unknown flag: $arg (use --patch | --minor | --major | --local-only)" >&2; exit 1 ;;
    esac
done

# Decide GitHub upload mode now so we can fail fast with clear errors before
# we waste time archiving.
if (( USE_GITHUB == 1 )); then
    if ! command -v gh >/dev/null 2>&1; then
        echo "ERROR: 'gh' CLI not found." >&2
        echo "  Install:   brew install gh" >&2
        echo "  Auth:      gh auth login" >&2
        echo "  Or run:    scripts/publish.sh --local-only (skip GitHub)" >&2
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "ERROR: 'gh' is installed but not authenticated. Run: gh auth login" >&2
        exit 1
    fi
    GITHUB_OWNER="$(resolve_github_owner)"
    if [[ -z "$GITHUB_OWNER" ]]; then
        echo "ERROR: Could not resolve GITHUB_OWNER. Set the env var or run gh auth login." >&2
        exit 1
    fi
    if ! gh repo view "$GITHUB_OWNER/$GITHUB_REPO" >/dev/null 2>&1; then
        echo "ERROR: GitHub repo '$GITHUB_OWNER/$GITHUB_REPO' not found or no access." >&2
        echo "  Create it (public so Sparkle can fetch the appcast):" >&2
        echo "    gh repo create $GITHUB_OWNER/$GITHUB_REPO --public --description 'Aurora updates'" >&2
        exit 1
    fi
    if [[ "$(gh repo view "$GITHUB_OWNER/$GITHUB_REPO" --json isEmpty --jq .isEmpty)" == "true" ]]; then
        echo "GitHub repo '$GITHUB_OWNER/$GITHUB_REPO' is empty — creating initial README commit."
        README_CONTENT="$(printf '# Aurora Releases\n\nPublic Sparkle appcast and DMG releases for Aurora.\n' | base64)"
        gh api \
            --method PUT \
            "repos/$GITHUB_OWNER/$GITHUB_REPO/contents/README.md" \
            -f message="Initialise releases repository" \
            -f content="$README_CONTENT" \
            -f branch="main" \
            >/dev/null
    fi
fi

# Compute RELEASE_BASE_URL: where the appcast points the <enclosure url=...>.
# Format must match where we upload the DMG below.
if [[ -z "${RELEASE_BASE_URL:-}" ]]; then
    if (( USE_GITHUB == 1 )); then
        RELEASE_BASE_URL="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/download/PLACEHOLDER_TAG"
    else
        RELEASE_BASE_URL="file://$RELEASES_DIR"
    fi
fi

# -------- 1. Read and bump version -------------------------------------------
CURRENT_VERSION="$(grep -m1 "MARKETING_VERSION = " "$PROJECT_FILE/project.pbxproj" \
                     | sed -E 's/.*MARKETING_VERSION = ([0-9.]+);.*/\1/')"
if [[ ! "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "ERROR: Could not parse current MARKETING_VERSION: '$CURRENT_VERSION'" >&2
    exit 1
fi

CURRENT_BUILD="$(grep -m1 "CURRENT_PROJECT_VERSION = " "$PROJECT_FILE/project.pbxproj" \
                    | sed -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/')"
if [[ ! "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Could not parse CURRENT_PROJECT_VERSION: '$CURRENT_BUILD'" >&2
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
NEW_BUILD=$((CURRENT_BUILD + 1))
RELEASE_TAG="v$NEW_VERSION"

# Now that we know the version, resolve the PLACEHOLDER_TAG.
RELEASE_BASE_URL="${RELEASE_BASE_URL/PLACEHOLDER_TAG/$RELEASE_TAG}"

echo "Publishing Aurora $CURRENT_VERSION → $NEW_VERSION"
if (( USE_GITHUB == 1 )); then
    echo "  GitHub target: $GITHUB_OWNER/$GITHUB_REPO   tag: $RELEASE_TAG"
fi
echo

# Write back into both Debug and Release configs in the pbxproj.
# Match the exact "MARKETING_VERSION = <ver>;" line to avoid clobbering numbers
# that look similar elsewhere.
/usr/bin/sed -i '' \
    -e "s/MARKETING_VERSION = $CURRENT_VERSION;/MARKETING_VERSION = $NEW_VERSION;/g" \
    -e "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" \
    "$PROJECT_FILE/project.pbxproj"

# Sanity: the changes actually happened.
if ! grep -q "MARKETING_VERSION = $NEW_VERSION;" "$PROJECT_FILE/project.pbxproj"; then
    echo "ERROR: MARKETING_VERSION did not update — aborting." >&2
    exit 1
fi
if ! grep -q "CURRENT_PROJECT_VERSION = $NEW_BUILD;" "$PROJECT_FILE/project.pbxproj"; then
    echo "ERROR: CURRENT_PROJECT_VERSION did not update — aborting." >&2
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

# -------- 4. Build the DMG (drag-to-Applications, no external tools) ---------
DMG_NAME="${PRODUCT_NAME}-${NEW_VERSION}.dmg"
DMG_PATH="$RELEASES_DIR/$DMG_NAME"
DMG_STAGING="$RELEASES_DIR/.dmg-staging-$$"
TMP_DMG="$RELEASES_DIR/.dmg-tmp-$$.dmg"
rm -f "$DMG_PATH" "$TMP_DMG"
rm -rf "$DMG_STAGING"

echo "Building DMG → $DMG_NAME"

# Stage: app + Applications symlink
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create a read-write DMG from the staging folder
hdiutil create \
    -srcfolder "$DMG_STAGING" \
    -volname "${PRODUCT_NAME} ${NEW_VERSION}" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,b=16" \
    -format UDRW \
    -quiet \
    "$TMP_DMG"

# Mount the RW DMG
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" \
    | grep "/Volumes" | awk -F'\t' '{print $NF}' | head -1)

# Use Finder via AppleScript to set icon positions and window layout
VOLNAME="${PRODUCT_NAME} ${NEW_VERSION}"
APP_BUNDLE="${PRODUCT_NAME}.app"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 860, 520}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "$APP_BUNDLE" of container window to {170, 185}
        set position of item "Applications" of container window to {490, 185}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Flush and detach
sync
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed read-only DMG
hdiutil convert "$TMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    -o "$DMG_PATH"

rm -f "$TMP_DMG"
rm -rf "$DMG_STAGING"

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

SIGN_OUTPUT="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$DMG_PATH")"
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
        sparkle:version=\"$NEW_BUILD\"
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
    TMP_INSERT="$(mktemp)"
    printf '%s\n' "$NEW_ITEM_XML" > "$TMP_INSERT"
    awk '
        NR==FNR { ins = ins $0 "\n"; next }
        /<\/title>/ && !done { print; printf "%s", ins; done=1; next }
        { print }
    ' "$TMP_INSERT" "$APPCAST" > "$TMP_APPCAST"
    mv "$TMP_APPCAST" "$APPCAST"
    rm -f "$TMP_INSERT"
fi

# -------- 7. Upload to GitHub Releases ---------------------------------------
# Uploads both the DMG and the updated appcast.xml as assets of the new
# release. We always reuse the same appcast.xml filename so Sparkle can fetch
# `…/releases/latest/download/appcast.xml` and get the most recent feed
# without ever knowing the version number.
if (( USE_GITHUB == 1 )); then
    echo
    echo "Uploading to GitHub Releases ($GITHUB_OWNER/$GITHUB_REPO @ $RELEASE_TAG)…"

    # If the release already exists (re-publish of the same version), delete
    # any conflicting assets so the upload is idempotent.
    if gh release view "$RELEASE_TAG" --repo "$GITHUB_OWNER/$GITHUB_REPO" >/dev/null 2>&1; then
        echo "  Release $RELEASE_TAG already exists — replacing assets."
        gh release upload "$RELEASE_TAG" "$DMG_PATH" "$APPCAST" \
            --repo "$GITHUB_OWNER/$GITHUB_REPO" \
            --clobber
    else
        gh release create "$RELEASE_TAG" \
            --repo "$GITHUB_OWNER/$GITHUB_REPO" \
            --title "Aurora $NEW_VERSION" \
            --notes "Automated release for Aurora $NEW_VERSION." \
            "$DMG_PATH" "$APPCAST"
    fi

    PUBLIC_APPCAST_URL="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/latest/download/appcast.xml"
fi

# -------- Done ---------------------------------------------------------------
echo
echo "✅ Published Aurora $NEW_VERSION"
echo
echo "   DMG       : $DMG_PATH         ($((DMG_SIZE_BYTES / 1024 / 1024)) MB)"
echo "   Appcast   : $APPCAST"

if (( USE_GITHUB == 1 )); then
    echo "   GitHub    : https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
    echo "   Feed URL  : $PUBLIC_APPCAST_URL"
    echo
    echo "Production app: menu Aurora > Check for Updates… should now show"
    echo "  '$NEW_VERSION available — Update Now'."
else
    echo "   Feed URL  : $RELEASE_BASE_URL/appcast.xml   (local-only)"
fi
