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
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-aurora}"

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
echo "Account: $SPARKLE_ACCOUNT"
echo

extract_public_key() {
    local output="$1"
    local line candidate

    while IFS= read -r line; do
        # Sparkle versions differ slightly in wording; accept either a bare
        # key line or a labelled "Public ... key: <base64>" line.
        if [[ "$line" == *":"* ]]; then
            candidate="${line##*:}"
        else
            candidate="$line"
        fi

        candidate="${candidate//[$' \t\r\n']/}"
        if [[ "$candidate" =~ ^[A-Za-z0-9+/=]{40,}$ ]]; then
            printf "%s" "$candidate"
            return 0
        fi
    done <<< "$output"

    return 1
}

# generate_keys stores the private key in Keychain. -p prints the existing
# public key, but on some Sparkle versions the "no key" message is printed to
# stdout, so validate before reusing it.
EXISTING_OUTPUT="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p 2>&1 || true)"
PUBLIC_KEY="$(extract_public_key "$EXISTING_OUTPUT" || true)"

if [[ -z "$PUBLIC_KEY" ]]; then
    echo "No existing key in Keychain — generating a new EdDSA key pair…"
    "$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT"
    GENERATED_OUTPUT="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p 2>&1 || true)"
    PUBLIC_KEY="$(extract_public_key "$GENERATED_OUTPUT" || true)"
else
    echo "Existing key found in Keychain. Reusing it."
fi

if [[ -z "$PUBLIC_KEY" ]]; then
    echo "ERROR: Could not read Sparkle public key after generation." >&2
    echo "Try running this manually to inspect the output:" >&2
    echo "  $GENERATE_KEYS --account $SPARKLE_ACCOUNT" >&2
    echo "  $GENERATE_KEYS --account $SPARKLE_ACCOUNT -p" >&2
    exit 1
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
