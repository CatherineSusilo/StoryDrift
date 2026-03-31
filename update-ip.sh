#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# update-ip.sh  —  run this every time you switch WiFi networks
#
#   cd /Users/catherinesusilo/StoryDrift && ./update-ip.sh
# ─────────────────────────────────────────────────────────────────────────────

PORT=3001
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS="$SCRIPT_DIR/Idle/Services/Secrets.swift"
PLIST="$SCRIPT_DIR/Idle/Resources/Info.plist"
BACKEND="$SCRIPT_DIR/backend"
LOG="/tmp/storydrift-backend.log"

# ── 1. Detect current LAN IP ─────────────────────────────────────────────────
IP=$(ipconfig getifaddr en0 2>/dev/null \
  || ipconfig getifaddr en1 2>/dev/null \
  || ipconfig getifaddr en2 2>/dev/null \
  || true)

if [ -z "$IP" ]; then
  echo "❌  Could not detect LAN IP. Are you on WiFi?"
  exit 1
fi

BASE_URL="http://$IP:$PORT"
echo "🔍  LAN IP: $IP"

# ── 2. Update Secrets.swift ───────────────────────────────────────────────────
sed -i '' \
  "s|static let apiBaseURL: String = \"http://[0-9.]*:[0-9]*\"|static let apiBaseURL: String = \"$BASE_URL\"|" \
  "$SECRETS"
echo "✅  Secrets.swift   → $BASE_URL"

# ── 3. Update Info.plist ATS exception ───────────────────────────────────────
sed -i '' \
  "s|<key>[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}</key>|<key>$IP</key>|" \
  "$PLIST"
echo "✅  Info.plist      → ATS exception → $IP"

# ── 4. Kill stale server ──────────────────────────────────────────────────────
pkill -f "tsx watch" 2>/dev/null || true
EXISTING_PID=$(lsof -ti :$PORT 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  kill "$EXISTING_PID" 2>/dev/null || true
  sleep 1
fi
echo "🛑  Cleared port $PORT"

# ── 5. Install deps if missing ────────────────────────────────────────────────
if [ ! -d "$BACKEND/node_modules" ]; then
  echo "📦  Installing dependencies…"
  (cd "$BACKEND" && npm install --silent)
fi

# ── 6. Start server ───────────────────────────────────────────────────────────
: > "$LOG"
(cd "$BACKEND" && nohup npm run dev >> "$LOG" 2>&1 &)
echo "🚀  Server starting (logs → $LOG)"

# ── 7. Poll for healthy or MongoDB error ─────────────────────────────────────
echo -n "⏳  Waiting"
RESULT=""
for i in $(seq 1 40); do
  sleep 1
  echo -n "."

  if curl -s --max-time 1 "http://localhost:$PORT/health" > /dev/null 2>&1; then
    RESULT="up"
    break
  fi

  if grep -ql "MongoDB Atlas\|Authentication failed\|ECONNREFUSED" "$LOG" 2>/dev/null; then
    RESULT="atlas"
    break
  fi
done
echo ""

# ── 8. Result ────────────────────────────────────────────────────────────────
if [ "$RESULT" = "up" ]; then
  echo "✅  Server is healthy at $BASE_URL"
  echo ""
  echo "📱  Backend URL : $BASE_URL"
  echo "📋  Server logs : tail -f $LOG"
  echo "👉  Rebuild Xcode (Cmd+B) to apply the new IP."

elif [ "$RESULT" = "atlas" ]; then
  PUBLIC_IP=$(curl -s --max-time 4 https://ipinfo.io/ip 2>/dev/null || echo "unknown")
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⚠️   MongoDB Atlas is blocking your PUBLIC IP: $PUBLIC_IP"
  echo ""
  echo "    FIX (30 seconds, do this once):"
  echo "    1. https://cloud.mongodb.com"
  echo "       → Network Access → + Add IP Address"
  echo "       → Allow Access from Anywhere  (0.0.0.0/0)"
  echo "       → Confirm  →  wait ~15s"
  echo "    2. Run again:  ./update-ip.sh"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1

else
  # Still waiting — MongoDB Atlas timeout can be very slow (30-60s)
  # Keep polling in the background and notify when ready
  PUBLIC_IP=$(curl -s --max-time 4 https://ipinfo.io/ip 2>/dev/null || echo "unknown")
  echo "⏳  Still connecting to MongoDB Atlas (can take up to 60s)…"
  echo "    Public IP: $PUBLIC_IP"
  echo ""
  echo "    If this keeps failing, whitelist your IP in Atlas:"
  echo "    https://cloud.mongodb.com → Network Access → Allow Access from Anywhere"
  echo ""
  echo "    Checking in background for 60 more seconds…"

  for i in $(seq 1 60); do
    sleep 1
    if curl -s --max-time 1 "http://localhost:$PORT/health" > /dev/null 2>&1; then
      echo "✅  Server is now healthy at $BASE_URL  (took ~$((i + 40))s total)"
      echo "👉  Rebuild Xcode (Cmd+B) to apply the new IP."
      exit 0
    fi
    if grep -ql "MongoDB Atlas\|Authentication failed" "$LOG" 2>/dev/null; then
      echo "❌  MongoDB Atlas rejected this IP."
      echo "    Whitelist $PUBLIC_IP at https://cloud.mongodb.com → Network Access"
      echo "    Then run:  ./update-ip.sh"
      exit 1
    fi
  done

  echo "❌  Server never came up. Last log:"
  tail -8 "$LOG"
  echo "📋  Full logs: tail -f $LOG"
  exit 1
fi
