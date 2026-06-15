#!/usr/bin/env python3
"""
Generate Aurora activation codes and license keys.

Usage:
  # Generate a new key pair (run once)
  python3 generate-license-key.py --gen-key

  # Generate an activation code (not bound to any UUID)
  python3 generate-license-key.py --activate

  # Generate with expiry (30 days from now)
  python3 generate-license-key.py --activate --expire-days 30

  # Get the hardware UUID of this Mac
  python3 generate-license-key.py --my-uuid

Keys are stored in ~/.aurora-license-keypair/
"""

import argparse
import base64
import json
import os
import platform
import secrets
import subprocess
import sys
import time
from pathlib import Path

KEY_DIR = Path.home() / ".aurora-license-keypair"
PRIVATE_KEY_FILE = KEY_DIR / "private_key.pem"
PUBLIC_KEY_FILE = KEY_DIR / "public_key.b64"


def get_hardware_uuid():
    """Get the IOPlatformUUID of this Mac."""
    try:
        result = subprocess.run(
            ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
            capture_output=True, text=True, check=True
        )
        for line in result.stdout.split("\n"):
            if "IOPlatformUUID" in line:
                # Format: "IOPlatformUUID" = "XXXX-XXXX-..."
                if '"' in line:
                    # Find the second quoted string
                    parts = line.split('"')
                    if len(parts) >= 4:
                        return parts[3]
    except Exception as e:
        print(f"Error getting hardware UUID: {e}", file=sys.stderr)
    return None


def base64url_encode(data: bytes) -> str:
    """Base64url encode without padding."""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def base64url_decode(s: str) -> bytes:
    """Base64url decode with padding."""
    s = s.replace("-", "+").replace("_", "/")
    padding = (4 - len(s) % 4) % 4
    s += "=" * padding
    return base64.b64decode(s)


def generate_key_pair():
    """Generate a new P256 ECDSA key pair."""
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives import serialization

    private_key = ec.generate_private_key(ec.SECP256R1())

    # Save private key (PEM)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )
    KEY_DIR.mkdir(parents=True, exist_ok=True)
    PRIVATE_KEY_FILE.write_bytes(private_pem)

    # Save public key (raw x963 format, base64)
    public_key = private_key.public_key()
    public_bytes = public_key.public_bytes(
        encoding=serialization.Encoding.X962,
        format=serialization.PublicFormat.UncompressedPoint
    )
    PUBLIC_KEY_FILE.write_text(base64.b64encode(public_bytes).decode("ascii"))

    print(f"✅ Key pair generated in {KEY_DIR}/")
    print(f"   Private key: {PRIVATE_KEY_FILE}")
    print(f"   Public key (paste into LicensingService.swift):")
    print(f"   {base64.b64encode(public_bytes).decode('ascii')}")
    print()
    print("Next steps:")
    print("  1. Copy the public key above into LicensingService.swift (publicKeyBase64)")
    print("  2. Generate license keys with: python3 generate-license-key.py --uuid <hardware-uuid>")


def load_private_key():
    """Load the private key from disk."""
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives import serialization

    if not PRIVATE_KEY_FILE.exists():
        print("No key pair found. Run with --gen-key first.", file=sys.stderr)
        sys.exit(1)

    private_pem = PRIVATE_KEY_FILE.read_bytes()
    return serialization.load_pem_private_key(private_pem, password=None)


def generate_activation_code(expire_days: int = 0):
    """Generate an activation code (not bound to any UUID)."""
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives import hashes

    private_key = load_private_key()

    # Random activation code
    code = secrets.token_hex(8).upper()

    payload = {"code": code, "feat": 0}
    if expire_days > 0:
        payload["exp"] = int(time.time()) + (expire_days * 86400)

    payload_bytes = json.dumps(payload, separators=(",", ":")).encode("utf-8")

    # Sign
    signature = private_key.sign(payload_bytes, ec.ECDSA(hashes.SHA256()))

    # Format key
    key = f"AURORA-{base64url_encode(payload_bytes)}-{base64url_encode(signature)}"
    return key


def main():
    parser = argparse.ArgumentParser(description="Aurora license key generator")
    parser.add_argument("--gen-key", action="store_true", help="Generate a new key pair")
    parser.add_argument("--my-uuid", action="store_true", help="Print this Mac's hardware UUID")
    parser.add_argument("--activate", action="store_true", help="Generate an activation code")
    parser.add_argument("--expire-days", type=int, default=0, help="Expiry in days from now (0 = no expiry)")
    args = parser.parse_args()

    if args.gen_key:
        generate_key_pair()
        return

    if args.my_uuid:
        uuid = get_hardware_uuid()
        if uuid:
            print(f"Hardware UUID: {uuid}")
        else:
            print("Could not determine hardware UUID.", file=sys.stderr)
            sys.exit(1)
        return

    if args.activate:
        key = generate_activation_code(args.expire_days)
        print(f"\nActivation code:")
        print(f"  {key}\n")
        if args.expire_days > 0:
            exp_date = time.strftime("%Y-%m-%d", time.localtime(time.time() + args.expire_days * 86400))
            print(f"  Expires: {exp_date}")
        else:
            print(f"  Expires: never")
        print(f"\n  Share this code. The user enters it in Aurora Settings → License.")
        print(f"  The app captures their UUID automatically on first activation.")
        return

    parser.print_help()


if __name__ == "__main__":
    main()
