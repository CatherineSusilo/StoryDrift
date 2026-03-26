#!/bin/bash

# Run this every time you switch WiFi networks:
#   ./update-ip.sh
#
# Updates the backend IP in:
#   1. Idle/Services/Secrets.swift      (apiBaseURL)
#   2. Idle/Resources/Info.plist        (NSAppTransportSecurity ATS exception)

set -e

# ── Detect current IP ────────────────────────────────────────────────────────
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)

if [ -z "$IP" ]; then
  echo "❌  Could not detect your IP. Are you connected to WiFi?"
  exit 1
fi

PORT=3001
BASE_URL="http://$IP:$PORT"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS="$SCRIPT_DIR/Idle/Services/Secrets.swift"
PLIST="$SCRIPT_DIR/Idle/Resources/Info.plist"

echo "🔍  Detected IP: $IP"

# ── 1. Update Secrets.swift ──────────────────────────────────────────────────
if [ ! -f "$SECRETS" ]; then
  echo "❌  Secrets.swift not found at $SECRETS"
  exit 1
fi

sed -i '' "s|static let apiBaseURL: String = \"http://[0-9.]*:[0-9]*\"|static let apiBaseURL: String = \"$BASE_URL\"|" "$SECRETS"
echo "✅  Secrets.swift   → $BASE_URL"

# ── 2. Update Info.plist ATS exception domain ────────────────────────────────
if [ ! -f "$PLIST" ]; then
  echo "❌  Info.plist not found at $PLIST"
  exit 1
fi

# Replace any existing ATS exception IP (matches any x.x.x.x inside the plist key)
sed -i '' "s|<key>[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}</key>|<key>$IP</key>|" "$PLIST"
echo "✅  Info.plist      → ATS exception domain set to $IP"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "📱  Backend URL: $BASE_URL"
echo "👉  Rebuild in Xcode (Cmd+B) to apply the changes."
