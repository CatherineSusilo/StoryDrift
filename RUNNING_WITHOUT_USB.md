# Running StoryDrift Without USB Connection

## Overview

**Good news!** The SmartSpectra SDK runs **entirely on-device** and does **not require a USB connection** to function. The USB cable is only needed for Xcode debugging, not for the SDK or vitals tracking.

## How It Works

### On-Device Processing
- SmartSpectra uses the device's **front camera** to capture your child's face
- All processing happens **locally on the iPhone** using Metal and CoreML
- Heart rate, breathing rate, and eye drowsiness are calculated in real-time
- No data is sent to external servers (except your own backend for storage)

### When USB is Actually Needed
The USB connection is only required for:
- ✅ Installing the app from Xcode
- ✅ Viewing Xcode console logs during development
- ✅ Xcode debugging (breakpoints, etc.)

The USB is **NOT** required for:
- ❌ Running the app normally
- ❌ SmartSpectra vitals tracking
- ❌ Camera operation
- ❌ Story playback
- ❌ Any normal app functionality

## Usage Instructions

### Option 1: Build and Run Wirelessly (Recommended)

1. **Initial Setup (one-time)**:
   ```bash
   # Connect iPhone via USB
   # In Xcode: Window → Devices and Simulators
   # Select your iPhone → Check "Connect via network"
   ```

2. **Build and Run**:
   - iPhone now appears in Xcode with a network icon 🌐
   - Click Run in Xcode — app installs wirelessly
   - App runs with full vitals tracking, no cable needed!

3. **Unplug and Use**:
   - Safely unplug the USB cable
   - App continues running with SmartSpectra active
   - Vitals tracking works normally
   - Xcode console still shows logs wirelessly

### Option 2: Build, Then Test Standalone

1. **Build with USB**:
   ```bash
   # Connect iPhone via USB
   # In Xcode, select your device and click Run
   # Wait for app to launch
   ```

2. **Stop Xcode Session**:
   - Click Stop (⏹) in Xcode
   - The app remains installed on your iPhone

3. **Unplug and Launch**:
   - Unplug USB cable
   - Launch "Idle" app from your iPhone home screen
   - App runs completely independently
   - SmartSpectra tracks vitals using the camera
   - All features work normally

### Option 3: TestFlight Distribution

For a true production experience:

1. **Archive and Upload**:
   ```bash
   # In Xcode: Product → Archive
   # Upload to TestFlight
   ```

2. **Install on Device**:
   - Install app via TestFlight
   - No USB connection ever needed
   - Works exactly like a production app

## Verifying It's Working

When SmartSpectra is running locally, you'll see:

1. **In the Console** (if connected wirelessly):
   ```
   [StoryVitalsTracker] 📱 SDK runs entirely on-device — USB connection not required
   [StoryVitalsTracker] ⚙️  Mode: continuous, camera: front
   [StoryVitalsTracker] ▶️  SDK started — continuous mode
   ```

2. **In the App**:
   - Drift score updates in real-time (0-100%)
   - Heart rate displays (e.g., "72 BPM")
   - Breathing rate shows (e.g., "14 breaths/min")
   - Vitals overlay visible during story

3. **On Dashboard**:
   - Drift meter shows current drowsiness
   - Recent stories display vitals data
   - Behavioral insights show trends

## Troubleshooting

### "Camera disabled — using synthetic drift"
**Cause**: `isCameraEnabled` is set to `false` in Settings  
**Fix**: Go to Settings → Enable "Camera Tracking"

### Vitals show as 0 BPM
**Causes**:
1. Face not visible to front camera
2. Poor lighting conditions
3. Camera permission not granted
4. SmartSpectra API key missing

**Fixes**:
- Ensure child's face is visible to camera
- Improve room lighting
- Check Settings → Privacy → Camera → Idle (enabled)
- Verify `SMARTSPECTRA_API_KEY` in `Config.xcconfig`

### App crashes when unplugged
**Cause**: This shouldn't happen! The SDK is designed for local operation.  
**Debug**:
1. Check Xcode console for error messages
2. Verify SmartSpectra API key is valid
3. Try wireless debugging to see crash logs
4. Check that all camera permissions are granted

### "No vitals data available"
**Cause**: SDK failed to initialize  
**Debug**:
- Check SmartSpectra API key is set and valid
- Verify iOS version is 15.0+
- Ensure physical device (not simulator)
- Check camera permission in device Settings

## Performance Tips

When running standalone (without USB):

1. **Battery Life**:
   - SmartSpectra uses camera and ML processing
   - Expect ~30-40% battery drain per hour
   - Keep device plugged into charger during long sessions

2. **Optimal Conditions**:
   - Well-lit room (not direct sunlight)
   - Child facing camera at ~30-50cm distance
   - Minimal head movement
   - Phone stable (not handheld)

3. **Resource Usage**:
   - Background apps closed for best performance
   - Device not overheating (can affect camera)
   - Sufficient storage space for logs

## Development Workflow

### Typical Development Cycle

```bash
# 1. Initial build with USB
xcodebuild -scheme Idle -destination 'name=iPhone' build

# 2. Test with wireless debugging
# (Xcode → Window → Devices → Connect via network)

# 3. Make code changes

# 4. Build and run wirelessly
# No cable needed!

# 5. Test unplugged operation
# Stop Xcode, launch app from home screen
```

### Console Logging Without USB

Enable wireless debugging to see logs even when unplugged:

```bash
# In Terminal on Mac
xcrun simctl spawn booted log stream --predicate 'processImagePath contains "Idle"'

# Or use Console.app
# File → Open → iPhone (network) → Filter: Idle
```

## Architecture Notes

### Why This Works

```
┌─────────────────────────────────────┐
│         iPhone (Unplugged)          │
│                                     │
│  ┌─────────────────────────────┐  │
│  │     StoryDrift App          │  │
│  │                             │  │
│  │  ┌────────────────────────┐ │  │
│  │  │  SmartSpectra SDK      │ │  │
│  │  │  • Runs on Metal       │ │  │
│  │  │  • Uses CoreML         │ │  │
│  │  │  • All local processing│ │  │
│  │  └────────────────────────┘ │  │
│  │           ↓                 │  │
│  │  ┌────────────────────────┐ │  │
│  │  │  VitalsManager         │ │  │
│  │  │  • Drift score calc    │ │  │
│  │  │  • Updates UI          │ │  │
│  │  └────────────────────────┘ │  │
│  └─────────────────────────────┘  │
│               ↓                    │
│        [Front Camera]              │
│         (Child's face)             │
└─────────────────────────────────────┘
         ↓ (WiFi/Cellular)
┌─────────────────────────────────────┐
│     Backend API (Optional)          │
│     • Stores vitals history         │
│     • Generates stories             │
└─────────────────────────────────────┘
```

### Components That Don't Need USB

- ✅ SmartSpectra SDK (on-device ML)
- ✅ Camera capture
- ✅ Signal processing
- ✅ VitalsManager
- ✅ Story playback
- ✅ Audio synthesis
- ✅ UI rendering
- ✅ Backend API calls (uses WiFi/Cellular)

### Components That Use USB (Optional)

- 🔌 Xcode debugging
- 🔌 Console logging
- 🔌 Initial app installation
- 🔌 Profiling/Instruments

## Conclusion

**SmartSpectra works perfectly without USB!** The cable is purely for development convenience. Your app is fully functional when unplugged and provides the same vitals tracking quality whether connected or standalone.

For the best user experience, consider distributing via TestFlight so parents never need to connect their iPhone to a computer at all.
