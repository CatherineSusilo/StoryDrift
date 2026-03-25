# Quick Start Guide - Idle Swift Migration

## ✅ Project Ready!

The Xcode project has been successfully created and is ready to open.

## 📂 What's Included

```
SwiftApp/
├── Idle.xcodeproj/           ✅ Xcode project (READY TO OPEN)
├── Idle.xcworkspace/         ✅ Workspace file
├── Idle/
│   ├── IdleApp.swift         ✅ Main app entry
│   ├── Models/
│   │   └── Models.swift      ✅ All data models
│   ├── Services/
│   │   ├── AuthManager.swift        ✅ Auth0 authentication
│   │   ├── APIService.swift         ✅ API client
│   │   └── SmartSpectraManager.swift ✅ Vitals monitoring
│   ├── Views/
│   │   ├── ContentView.swift        ✅
│   │   ├── LoginView.swift          ✅
│   │   ├── LoadingView.swift        ✅
│   │   ├── MainTabView.swift        ✅
│   │   ├── ChildDashboardView.swift ✅
│   │   ├── ChildOnboardingView.swift ✅
│   │   └── BehavioralStatsView.swift ✅
│   └── Resources/
│       ├── Info.plist        ✅ App config
│       └── Assets.xcassets/  ✅ App icon & colors
└── README.md                 📖 Full documentation
```

## 🚀 How to Open & Run

### Method 1: Double-Click (Easiest)
1. Navigate to `SwiftApp/` folder in Finder
2. Double-click `Idle.xcodeproj`
3. Xcode will open automatically

### Method 2: Terminal
```bash
cd /Users/catherinesusilo/HackCanada2026/SwiftApp
open Idle.xcodeproj
```

### Method 3: Xcode File Menu
1. Open Xcode
2. File → Open
3. Navigate to `SwiftApp/Idle.xcodeproj`
4. Click Open

## ⚙️ Configuration Required

### Before Building:

1. **Add Development Team**
   - In Xcode, select the project in navigator
   - Go to "Signing & Capabilities" tab
   - Select your development team in "Team" dropdown
   - Or enable "Automatically manage signing"

2. **Update Auth0 Credentials**
   - Open `Services/AuthManager.swift`
   - Replace these values:
   ```swift
   private let domain = "YOUR_AUTH0_DOMAIN"
   private let clientId = "YOUR_AUTH0_CLIENT_ID"
   ```

3. **Update API URL**
   - Open `Services/APIService.swift`
   - Update:
   ```swift
   static let baseURL = "http://localhost:3000"  // or your production URL
   ```

4. **Bundle Identifier (Optional)**
   - In Xcode project settings
   - Change from `com.hackcanada.idle` to your preferred identifier

## 📦 Dependencies

The project is configured to automatically fetch the SmartSpectra SDK via Swift Package Manager. When you first build:

1. Xcode will show "Fetching Package Dependencies"
2. This may take 1-2 minutes
3. If it fails, go to File → Packages → Reset Package Caches

## 🏗️ Building the App

1. Select a simulator or device from the scheme selector (top toolbar)
2. Press **⌘R** or click the ▶️ Play button
3. First build may take 2-3 minutes (compiling + fetching dependencies)
4. Camera features require a physical device (simulators won't work for vitals)

## 📱 Testing on Device

For SmartSpectra camera monitoring, you MUST use a physical iPhone:

1. Connect your iPhone via USB
2. Select it from the device menu in Xcode
3. Trust the computer on your iPhone if prompted
4. Build & Run
5. Grant camera permissions when prompted

## ⚠️ Common Issues

### Issue: "No such module 'SmartSpectraSwiftSDK'"
**Fix:** 
- File → Packages → Reset Package Caches
- Clean build folder (⌘⇧K)
- Rebuild (⌘B)

### Issue: "Code signing error"
**Fix:**
- Select your development team in Signing & Capabilities
- Or change bundle identifier to something unique

### Issue: "Camera not working"
**Fix:**
- Must use physical device (not simulator)
- Check camera permissions in Settings → Privacy

### Issue: "Build failed: missing files"
**Fix:**
- The project.pbxproj expects all Swift files to exist
- Make sure all files from the migration are present
- Check that paths are correct

## 🎯 Next Steps

Once the project builds successfully:

1. ✅ Test login flow (simulated - no actual Auth0 yet)
2. ✅ Create a child profile
3. ✅ Explore the dashboard
4. 🔨 Implement story playback view
5. 🔨 Add audio integration (ElevenLabs)
6. 🔨 Complete interactive elements

## 📝 Current Status

**What Works:**
- ✅ App launches and shows login screen
- ✅ Navigation structure (tabs)
- ✅ Child profile creation flow
- ✅ Dashboard with stats
- ✅ Analytics views
- ✅ SmartSpectra SDK integration (needs testing)

**What Needs Work:**
- ⏳ Story setup & theme selection
- ⏳ Story playback with narration
- ⏳ Audio integration
- ⏳ Real Auth0 authentication
- ⏳ Image generation display
- ⏳ Drawing canvas for interactive elements

## 🆘 Need Help?

If you encounter issues:
1. Check the full [README.md](README.md) for detailed documentation
2. Verify all configuration steps above
3. Check Xcode console for error messages
4. Ensure backend is running if testing API calls

---

**Ready to build?** Open `Idle.xcodeproj` and press ⌘R!
