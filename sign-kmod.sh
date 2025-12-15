#!/bin/bash

# ============================================
#  Fedora Secure Boot Module Signing Script
#  Options:
#    -d  Use default akmods key
#    -n  Create a new keypair and use it
#  Usage:
#    sign-module [-d|-n] <module_name>
# ============================================

MODE=""
MODULE_NAME=""

# --- Parse options ---
while getopts "dn" opt; do
    case "$opt" in
        d) MODE="default" ;;
        n) MODE="new" ;;
        *) echo "Usage: sign-module [-d|-n] <module_name>"; exit 1 ;;
    esac
done
shift $((OPTIND-1))
MODULE_NAME="$1"

# --- Check module name ---
if [[ -z "$MODULE_NAME" ]]; then
    echo "❌ Error: No module name provided."
    echo "Usage: sign-module [-d|-n] <module_name>"
    exit 1
fi

# --- Paths ---
SIGN_FILE="/usr/src/kernels/$(uname -r)/scripts/sign-file"

if [[ ! -f "$SIGN_FILE" ]]; then
    echo "❌ sign-file script not found: $SIGN_FILE"
    echo "Install kernel-devel: sudo dnf install kernel-devel-$(uname -r)"
    exit 1
fi

MODULE_PATH=$(modinfo -n "$MODULE_NAME" 2>/dev/null)
if [[ ! -f "$MODULE_PATH" ]]; then
    echo "❌ Module file not found for '$MODULE_NAME'"
    exit 1
fi

# --- Determine key paths ---
if [[ "$MODE" == "default" ]]; then
    PRIVATE_KEY="/etc/pki/akmods/private/private_key.priv"
    PUBLIC_CERT="/etc/pki/akmods/certs/public_key.der"
    echo "🔑 Using default akmods key..."
elif [[ "$MODE" == "new" ]]; then
    KEY_DIR="/etc/pki/signing_keys"
    mkdir -p "$KEY_DIR"
    PRIVATE_KEY="$KEY_DIR/private_key.priv"
    PUBLIC_CERT="$KEY_DIR/public_key.der"

    echo "🔐 Generating new signing keypair in $KEY_DIR..."
    sudo openssl genpkey -algorithm RSA -out "$PRIVATE_KEY" -pkeyopt rsa_keygen_bits:2048
    sudo openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_CERT"

    echo "✅ New keypair created."
    echo "You may need to enroll $PUBLIC_CERT into MOK if Secure Boot is enabled:"
    echo "sudo mokutil --import $PUBLIC_CERT"
else
    echo "❌ You must specify -d (default) or -n (new) key mode"
    exit 1
fi

# --- Sign the module ---
echo "🔐 Signing module: $MODULE_PATH"
sudo "$SIGN_FILE" sha256 "$PRIVATE_KEY" "$PUBLIC_CERT" "$MODULE_PATH"

if [[ $? -ne 0 ]]; then
    echo "❌ Signing failed."
    exit 1
fi

# --- Update module dependencies ---
sudo depmod -a

echo "✅ Module '$MODULE_NAME' signed successfully!"
echo "You can now load it with:"
echo "   sudo modprobe $MODULE_NAME"
