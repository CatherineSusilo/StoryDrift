#!/bin/bash

# Gets your current Mac IP and updates Config.xcconfig automatically.
# Run this every time you switch WiFi: ./update-ip.sh

IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)

if [ -z "$IP" ]; then
  echo "❌ Could not detect your IP. Are you connected to WiFi?"
  exit 1
fi

XCCONFIG="/Users/catherinesusilo/StoryDrift/Idle/Resources/Config.xcconfig"

# Replace the API_BASE_URL line
sed -i '' "s|API_BASE_URL = .*|API_BASE_URL = http:$()//$IP:3001|" "$XCCONFIG"

echo "✅ IP updated to $IP"
echo "📱 API_BASE_URL = http://$IP:3001"
echo "👉 Rebuild the app in Xcode to apply the change."
