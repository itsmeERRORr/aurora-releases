#!/usr/bin/env bash
#
# One-time setup: generate the EdDSA key pair Sparkle uses to sign updates.
#
# - Private key  : stored in the macOS Keychain (Sparkle's generate_keys does this).
# - Public  key  : printed to stdout AND copied to clipboard so you can paste it
#                  into commanderonev2/Info.plist as the value of SUPublicEDKey.
#
# Run this exactly once per machine. To rotate the key, run again — the old
# entry in Keychain is replaced.
#
# Prerequisite: the Sparkle SwiftPM package must already be added in Xcode
# (File > Add Package Dependencies > https://github.com/sparkle-project/Sparkle),
# and you must have built the project at least once so the tool exists on disk.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_sparkle_tool() {
    local tool_name="$1"
    find "$HOME/Library/Developer/Xcode/DerivedData" \
        -name "$tool_name" \
        -path "*Sparkle*/bin/*" \
        -type f \
        2>/dev/null | head -1
}

GENERATE_KEYS="$(find_sparkle_tool generate_keys)"

if [[ -z "$GENERATE_KEYS" ]]; then
    echo "ERROR: Sparkle's generate_keys tool not found." >&2
    echo "Open Xcode and:" >&2
    echo "  1) File > Add Package Dependencies > https://github.com/sparkle-project/Sparkle" >&2
    echo "  2) Build the project once (⌘B)." >&2
    echo "Then re-run this script." >&2
    exit 1
fi

echo "Using: $GENERATE_KEYS"
echo

# generate_keys prints the public key to stderr and stores the private key in
# Keychain. -p prints the existing public key if one is already in Keychain.
PUBLIC_KEY="$("$GENERATE_KEYS" -p 2>/dev/null || true)"

if [[ -z "$PUBLIC_KEY" ]]; then
    echo "No existing key in Keychain — generating a new EdDSA key pair…"
    "$GENERATE_KEYS"
    PUBLIC_KEY="$("$GENERATE_KEYS" -p)"
else
    echo "Existing key found in Keychain. Reusing it."
fi

echo
echo "✅ Public key (paste into Info.plist as SUPublicEDKey):"
echo "    $PUBLIC_KEY"
echo

# Copy to clipboard for convenience
if command -v pbcopy >/dev/null 2>&1; then
    printf "%s" "$PUBLIC_KEY" | pbcopy
    echo "(also copied to clipboard)"
fi
