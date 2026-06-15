#!/usr/bin/env bash
set -euo pipefail

PROD_DOMAIN="errormedia.commanderonev2"
BETA_DOMAIN="errormedia.commanderonev2.beta"

PROD_SUPPORT="$HOME/Library/Application Support/commanderonev2"
BETA_SUPPORT="$HOME/Library/Application Support/commanderonev2-beta"

PROD_PLIST="$HOME/Library/Preferences/${PROD_DOMAIN}.plist"
BETA_PLIST="$HOME/Library/Preferences/${BETA_DOMAIN}.plist"

echo "=== Aurora: prod → beta data migration ==="
echo ""

echo "[1/3] Flushing preferences cache..."
killall cfprefsd 2>/dev/null || true
sleep 0.5

echo "[2/3] Copying UserDefaults plist ($PROD_DOMAIN → $BETA_DOMAIN)..."
if [ ! -f "$PROD_PLIST" ]; then
    echo "      ERROR: prod plist not found at $PROD_PLIST"
    exit 1
fi
cp "$PROD_PLIST" "$BETA_PLIST"
KEY_COUNT=$(plutil -p "$BETA_PLIST" 2>/dev/null | grep -c "eventFolder\|eventSidebar\|importHistory" || echo 0)
echo "      OK – $KEY_COUNT event-related keys copied"

echo "[3/3] Copying Application Support data..."
for item in finalized_events.json totalStats.json event_stats_cache event_banners; do
    src="$PROD_SUPPORT/$item"
    dst="$BETA_SUPPORT/$item"
    if [ -e "$src" ]; then
        if [ -d "$src" ]; then
            rm -rf "$dst"
            cp -r "$src" "$dst"
        else
            cp -f "$src" "$dst"
        fi
        echo "      Copied: $item"
    else
        echo "      Skipped (not found): $item"
    fi
done

echo ""
echo "[!] Flushing preferences cache again..."
killall cfprefsd 2>/dev/null || true

echo ""
echo "Done!"
echo "Note: security-scoped bookmarks may need re-linking in the beta app."
echo "Open the beta and navigate to each event folder to reauthorize access."
