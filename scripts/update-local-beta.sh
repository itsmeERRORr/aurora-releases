#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/commanderonev2.xcodeproj"
INSTALL_DIR="$ROOT_DIR/JoaoPhotos"
TARGET_APP="$INSTALL_DIR/Aurora Beta.app"
BACKUP_APP="$INSTALL_DIR/.Aurora-Beta.previous.app"
BUILD_DIR="$ROOT_DIR/.joaophotos-build-beta"
SOURCE_APP="$BUILD_DIR/Build/Products/Debug/Aurora Beta.app"
LOG_FILE="$ROOT_DIR/JoaoPhotos/update-beta.log"
BUNDLE_ID="errormedia.commanderonev2.beta"

mkdir -p "$INSTALL_DIR"
: > "$LOG_FILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"Aurora Beta Update\"" >/dev/null 2>&1 || true
}

fail() {
  log "ERROR: $*"
  notify "Beta update failed. Check JoaoPhotos/update-beta.log"
  exit 1
}

log "Starting local Beta update"
log "Root: $ROOT_DIR"
log "Project: $PROJECT_FILE"
log "Target app: $TARGET_APP"

[[ -d "$PROJECT_FILE" ]] || fail "Xcode project not found: $PROJECT_FILE"

if ! /usr/bin/xcode-select -p | grep -q "/Applications/Xcode.app/Contents/Developer"; then
  fail "xcode-select is not pointing at Xcode. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

notify "Building Beta version..."
rm -rf "$BUILD_DIR"

/usr/bin/xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme commanderonev2 \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  build >> "$LOG_FILE" 2>&1 || fail "xcodebuild failed"

[[ -d "$SOURCE_APP" ]] || fail "Built app not found: $SOURCE_APP"

log "Quitting running Beta app"
/usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" >> "$LOG_FILE" 2>&1 || true
sleep 1

notify "Installing Beta version..."
rm -rf "$BACKUP_APP"
if [[ -d "$TARGET_APP" ]]; then
  mv "$TARGET_APP" "$BACKUP_APP"
fi

if ! /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP" >> "$LOG_FILE" 2>&1; then
  log "Install failed; restoring previous Beta app"
  rm -rf "$TARGET_APP"
  if [[ -d "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$TARGET_APP"
  fi
  fail "Failed to install new Beta app"
fi

rm -rf "$BACKUP_APP"
log "Installed new Beta app"

notify "Relaunching Beta..."
/usr/bin/open "$TARGET_APP" >> "$LOG_FILE" 2>&1 || fail "Failed to relaunch Beta app"
log "Beta update complete"
notify "Beta update complete"
