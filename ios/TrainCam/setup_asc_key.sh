#!/bin/bash
# Setup App Store Connect API key for Fastlane
# Run this ONCE after downloading your .p8 key from App Store Connect
#
# Generate a key at:
#   https://appstoreconnect.apple.com/access/integrations/api
#   → Team Keys → "+" → Name: "Fastlane" → Access: "Admin"
#   → Download the .p8 file (you can only download it ONCE)
#
# Then run:
#   ./setup_asc_key.sh <key_id> <issuer_id> <path_to_p8_file>
#
# Example:
#   ./setup_asc_key.sh ABC1234567 69a6de7e-xxxx-xxxx-xxxx-xxxxxxxxxxxx ~/Downloads/AuthKey_ABC1234567.p8

set -euo pipefail

if [ $# -ne 3 ]; then
    echo "Usage: $0 <key_id> <issuer_id> <path_to_p8_file>"
    echo ""
    echo "Get these from App Store Connect → Users and Access → Integrations → API Keys"
    echo "  key_id:     The Key ID shown in the keys list"
    echo "  issuer_id:  The Issuer ID shown at the top of the page"
    echo "  p8_file:    Path to the downloaded AuthKey_XXXXX.p8 file"
    exit 1
fi

KEY_ID="$1"
ISSUER_ID="$2"
P8_FILE="$3"

if [ ! -f "$P8_FILE" ]; then
    echo "Error: File not found: $P8_FILE"
    exit 1
fi

# Store key in fastlane directory (gitignored)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$SCRIPT_DIR/fastlane"
cp "$P8_FILE" "$SCRIPT_DIR/fastlane/AuthKey.p8"

# Create the JSON key file Fastlane expects
cat > "$SCRIPT_DIR/fastlane/asc_key.json" << EOF
{
  "key_id": "$KEY_ID",
  "issuer_id": "$ISSUER_ID",
  "key": "$(cat "$P8_FILE")",
  "in_house": false
}
EOF

echo "✅ API key configured!"
echo "   Key ID:    $KEY_ID"
echo "   Issuer ID: $ISSUER_ID"
echo "   Stored at: $SCRIPT_DIR/fastlane/asc_key.json"
echo ""
echo "Now run: cd ios/TrainCam && fastlane create_app"
