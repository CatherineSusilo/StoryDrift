# Idle - Native Swift Migration

This folder contains the native Swift/SwiftUI migration of the Idle adaptive bedtime story app.

## Status: 🚧 In Progress

This migration converts the React/TypeScript web app into a fully native iOS application using SwiftUI.

## ✅ Completed

### Core Architecture
- **App Structure**: Main app entry point with environment setup
- **Authentication**: Auth0 integration with ASWebAuthenticationSession
- **API Service**: Complete REST API client for backend communication
- **Models**: All data models migrated from TypeScript interfaces

### Services
- `AuthManager`: Handles Auth0 authentication flow
- `APIService`: Generic API client with typed requests
- `SmartSpectraManager`: Vitals monitoring with drift score calculation

### Views Implemented
- ✅ `LoginView`: Auth0 login with native UI
- ✅ `LoadingView`: Animated loading state
- ✅ `MainTabView`: Tab-based navigation structure
- ✅ `ChildDashboardView`: Home dashboard with stats and recent stories
- ✅ `ChildOnboardingView`: Multi-step child profile creation
- ✅ `BehavioralStatsView`: Analytics and vitals trends
- ✅ `StoryArchiveView`: Story history browser
- ✅ `SettingsView`: Account and profile management

## 🔨 To-Do

### High Priority
- [ ] `StorySetupView`: Theme selection and story configuration
- [ ] `StoryPlaybackView`: Live story narration with audio
- [ ] `DriftMeterView`: Real-time drift score visualization
- [ ] `InteractiveElementsView`: Choices, quizzes, drawing prompts
- [ ] `SummaryView`: Post-story completion screen
- [ ] Audio playback integration (ElevenLabs API)
- [ ] Image generation pipeline integration (Gemini 2.0 Flash Exp)

### Medium Priority
- [ ] Offline story caching
- [ ] Voice cloning setup flow
- [ ] Drawing canvas for interactive elements
- [ ] Export vitals data to Excel
- [ ] Push notifications for bedtime reminders
- [ ] Widget for quick story access

### Nice to Have
- [ ] iPad optimization
- [ ] Apple Watch companion app
- [ ] HealthKit integration
- [ ] Family Sharing support
- [ ] Siri shortcuts

## 🏗️ Architecture

```
SwiftApp/
├── Idle/
│   ├── IdleApp.swift           # Main app entry
│   ├── Models/
│   │   └── Models.swift        # All data models
│   ├── Services/
│   │   ├── AuthManager.swift   # Auth0 authentication
│   │   ├── APIService.swift    # API client
│   │   └── SmartSpectraManager.swift  # Vitals monitoring
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── LoginView.swift
│   │   ├── LoadingView.swift
│   │   ├── MainTabView.swift
│   │   ├── ChildDashboardView.swift
│   │   ├── ChildOnboardingView.swift
│   │   ├── BehavioralStatsView.swift
│   │   └── [More views...]
│   ├── ViewModels/
│   ├── Utils/
│   ├── Components/
│   └── Resources/
│       └── Info.plist
└── Idle.xcodeproj/
```

## 🔧 Setup Instructions

### Prerequisites
1. Xcode 15.0 or later
2. iOS 17.0+ deployment target
3. CocoaPods or Swift Package Manager
4. SmartSpectra SDK access

### Configuration

1. **Update Auth0 credentials** in `Services/AuthManager.swift`:
```swift
private let domain = "YOUR_AUTH0_DOMAIN"
private let clientId = "YOUR_AUTH0_CLIENT_ID"
```

2. **Update API base URL** in `Services/APIService.swift`:
```swift
static let baseURL = "https://your-backend-url.com"
```

3. **Add SmartSpectra SDK**:
   - Add the SDK to your project via SPM or CocoaPods
   - Ensure camera permissions are configured

### Dependencies

Add these Swift packages:
- **SmartSpectraSwiftSDK**: Contactless vitals monitoring
- **Auth0**: Authentication (if using Auth0 SDK)
- **Alamofire** (optional): Enhanced networking

## 🎨 Design System

The app uses a custom dark theme with:
- Primary: Purple (#8B5CF6)
- Secondary: Blue (#3B82F6)
- Accent: Cyan (#06B6D4)
- Background: Dark gradients
- Typography: San Francisco (system default)

## 📱 Screenshots

(Screenshots will be added as views are implemented)

## 🔐 Security Note

This code contains placeholder Auth0 configuration. **Never commit real credentials to version control.** Use:
- `.xcconfig` files for environment-specific settings
- Environment variables
- Xcode configuration settings

## 🚀 Building & Running

1. Open `Idle.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Update bundle identifier if needed
4. Build and run on simulator or device (camera required for vitals)

## 📝 Migration Notes

### Key Differences from Web Version

1. **Authentication**: Native ASWebAuthenticationSession instead of Auth0 React SDK
2. **Navigation**: Tab-based + navigation stack vs React Router
3. **State Management**: @StateObject/@ObservedObject instead of React hooks
4. **Styling**: SwiftUI declarative views instead of Tailwind CSS
5. **Vitals Integration**: Direct SmartSpectra SDK instead of bridge layer

### API Compatibility

The Swift app communicates with the same Node.js backend as the web version. All endpoints remain unchanged.

## 🤝 Contributing

When adding new views:
1. Follow the existing naming conventions
2. Use `@EnvironmentObject` for shared state
3. Keep views focused and composable
4. Add preview providers for Xcode canvas

## 📄 License

Same as the main project.
