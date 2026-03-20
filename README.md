# StoryDrift 🌙✨

> **AI-powered bedtime stories with real-time vitals monitoring for personalized children's sleep support**

StoryDrift is a native iOS app that generates dynamic, personalized bedtime stories while monitoring your child's vital signs using SmartSpectra's contactless technology. The app adapts story pacing and content in real-time based on the child's drift-to-sleep progression.

![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-green.svg)
![Status](https://img.shields.io/badge/Status-Complete-success.svg)

## ✨ Features

### 🎪 Core Features
- **Personalized Story Generation**: AI-powered stories customized to your child's interests, age, and mood
- **Real-time Vitals Monitoring**: Contactless heart rate and breathing rate tracking via SmartSpectra SDK
- **Drift Score Calculation**: Dynamic sleep progression tracking with 0-100% drift scoring
- **Adaptive Pacing**: Stories automatically adjust based on child's relaxation state
- **Interactive Elements**: Choices, quizzes, and drawing activities to engage children
- **Audio Narration**: ElevenLabs premium voice synthesis with multiple narrator options
- **Story Archive**: Browse and replay previous bedtime stories

### 📊 Analytics & Insights
- **Behavioral Statistics**: Track sleep onset time, story completion rates, and drift patterns
- **Vitals History**: Monitor heart rate and breathing trends over time
- **Story Performance**: See which themes and story types work best for your child
- **Dashboard**: Quick overview of recent stories, average drift scores, and key metrics

### 🎨 User Experience
- **Beautiful SwiftUI Interface**: Native iOS design with smooth animations
- **Dark Mode Optimized**: Gradient backgrounds perfect for bedtime
- **Child Profiles**: Support for multiple children with individual preferences
- **Theme Browser**: 25+ story themes across 5 categories (Adventure, Nature, Fantasy, Educational, Cozy)

## 🏗️ Architecture

### Technology Stack
- **Framework**: SwiftUI + Combine
- **Language**: Swift 5.9
- **Minimum iOS**: 16.0+
- **Architecture**: MVVM with @StateObject/@ObservableObject
- **Networking**: URLSession with async/await
- **Audio**: AVFoundation + AVSpeechSynthesizer
- **Charts**: Swift Charts (iOS 16+)
- **Drawing**: PencilKit for interactive canvas

### Project Structure

```
StoryDrift/
├── Idle/
│   ├── IdleApp.swift              # Main app entry point
│   ├── Models.swift                # Data models (Child, Story, Vitals, etc.)
│   │
│   ├── Services/                   # Business logic layer
│   │   ├── AuthManager.swift      # Auth0 authentication
│   │   ├── APIService.swift       # Backend API client
│   │   ├── SmartSpectraManager.swift  # Vitals monitoring
│   │   └── AudioService.swift     # ElevenLabs & TTS audio
│   │
│   ├── Views/                      # Screen-level views
│   │   ├── LoginView.swift        # Auth0 login
│   │   ├── LoadingView.swift      # Loading states
│   │   ├── ContentView.swift      # Root navigation
│   │   ├── MainTabView.swift      # Tab bar controller
│   │   ├── ChildDashboardView.swift  # Main dashboard
│   │   ├── ChildOnboardingView.swift  # Child profile creation
│   │   ├── BehavioralStatsView.swift  # Analytics dashboard
│   │   ├── StorySetupView.swift   # Story configuration
│   │   ├── StoryPlaybackView.swift  # Story narration
│   │   ├── StorySummaryView.swift  # Post-story completion
│   │   ├── StoryArchiveView.swift  # Story history
│   │   ├── StoryThemesView.swift  # Theme browser
│   │   └── SettingsView.swift     # App settings
│   │
│   └── Components/                 # Reusable UI components
│       ├── DriftMeterView.swift   # Drift visualization
│       ├── VitalsMonitorView.swift  # Vitals display
│       └── InteractiveElementsView.swift  # Story interactions
│
├── Idle.xcodeproj/                 # Xcode project configuration
└── README.md
```

## ✅ Migration Complete

All original React/TypeScript components have been successfully migrated to native SwiftUI:

### Services (4/4) ✅
- ✅ AuthManager - Auth0 authentication with ASWebAuthenticationSession
- ✅ APIService - Complete REST API client with async/await
- ✅ SmartSpectraManager - Vitals monitoring with drift calculation
- ✅ AudioService - ElevenLabs API + TTS fallback

### Views (12/12) ✅
- ✅ LoginView - Auth0 native login flow
- ✅ LoadingView - Animated loading states
- ✅ ContentView - Root navigation controller
- ✅ MainTabView - Tab-based navigation
- ✅ ChildDashboardView - Home dashboard with stats
- ✅ ChildOnboardingView - 4-step profile creation
- ✅ BehavioralStatsView - Analytics with charts
- ✅ StorySetupView - Theme selection & configuration
- ✅ StoryPlaybackView - Live narration with audio
- ✅ StorySummaryView - Post-story completion
- ✅ StoryArchiveView - Story history browser
- ✅ StoryThemesView - Categorized theme browser
- ✅ SettingsView - App configuration

### Components (3/3) ✅
- ✅ DriftMeterView - Circular progress visualization
- ✅ VitalsMonitorView - Real-time vitals display
- ✅ InteractiveElementsView - Choices, quizzes, drawing

## 🚀 Getting Started

### Prerequisites
1. **Xcode 15.0+** installed
2. **macOS 14.0 (Sonoma)+** recommended
3. **iOS 16.0+ device or simulator**
4. **SmartSpectra SDK** from Presage Health

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/StoryDrift.git
cd StoryDrift
```

2. **Open in Xcode**
```bash
open Idle.xcodeproj
```

3. **Install SmartSpectra SDK**
   - Download from [Presage Health](https://www.presagehealth.com/)
   - Add framework to: Target → General → Frameworks, Libraries, and Embedded Content

4. **Build and Run**
   - Select target device/simulator
   - Press `Cmd + R` or click ▶️ Run

## ⚙️ Configuration

### Auth0 Setup

**1. Create Auth0 Application**
- Go to [Auth0 Dashboard](https://manage.auth0.com/)
- Create new "Native" application
- Copy Domain and Client ID

**2. Configure Callback URLs**
```
storydrift://YOUR_TENANT.auth0.com/ios/com.storydrift.Idle/callback
```

**3. Update AuthManager.swift**
```swift
private let domain = "your-tenant.auth0.com"
private let clientId = "your_client_id_here"
```

### API Configuration

Update `APIService.swift`:
```swift
private let baseURL = "http://your-backend-url/api"
```

### ElevenLabs (Optional)

For premium audio narration:
```bash
export ELEVENLABS_API_KEY="your_api_key_here"
```

## 📱 Usage

### First Time Setup
1. Launch app → "Sign in with Auth0"
2. Create child profile (name, age, interests, bedtime)

### Creating Stories
1. Dashboard → "New Story"
2. Select theme or search
3. Choose tone (Calm/Exciting/Educational)
4. Set story length (5-20 min)
5. Position camera for vitals
6. "Start Story"

### During Playback
- **Drift Meter**: Real-time 0-100% sleep progression
- **Vitals**: Heart rate, breathing, signal quality
- **Interactions**: Choices, quizzes, drawing
- **Auto-pause**: Stops at 90% drift (child asleep)

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| SmartSpectra not found | Link SDK in Build Phases → Link Binary With Libraries |
| Auth0 login fails | Verify callback URL matches Info.plist |
| No audio | Check ElevenLabs key, enable TTS fallback, unmute device |
| Vitals not updating | Grant camera permissions, ensure good lighting |
| Stories not saving | Verify backend API reachable, check Auth0 token |

## 📝 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/auth/verify` | Verify Auth0 token |
| `GET` | `/children` | Get all child profiles |
| `POST` | `/children` | Create new child profile |
| `GET` | `/stories?childId=:id` | Get stories for child |
| `POST` | `/generate` | Generate new story |
| `POST` | `/vitals` | Post vitals data |
| `GET` | `/statistics/:childId` | Get behavioral stats |

## 🎨 Design

**Color Palette**:
- Primary: Purple (#8B5CF6)
- Secondary: Blue (#3B82F6)
- Accent: Cyan (#06B6D4)
- Background: Dark gradients

**Typography**: San Francisco (iOS system font)

## 📄 License

Proprietary - All rights reserved.

## 🙏 Acknowledgments

- **SmartSpectra SDK** by Presage Health
- **Auth0** for authentication
- **ElevenLabs** for voice synthesis
- **OpenAI** for story generation

---

**Built with ❤️ for better bedtime routines**
