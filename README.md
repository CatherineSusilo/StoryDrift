# StoryDrift 🌙✨

> **AI-powered bedtime stories with real-time vitals monitoring**

Native iOS app that generates personalized bedtime stories while monitoring your child's vital signs using contactless camera technology. Stories adapt in real-time based on the child's sleep progression.

![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-green.svg)

## ✨ Features

- **Personalized Stories**: AI-generated tales customized to your child's interests and age
- **Real-time Vitals**: Contactless heart rate and breathing tracking via SmartSpectra SDK
- **Drift Score**: 0-100% sleep progression with adaptive story pacing
- **Educational Content**: Curriculum-based lessons with interactive minigames
- **Parental Controls**: 6-digit PIN protection with child/parent modes
- **Story Archive**: Browse and replay previous bedtime stories
- **Voice Narration**: Premium ElevenLabs voices with TTS fallback

## 🏗️ Tech Stack

- **Framework**: SwiftUI + Combine
- **Language**: Swift 5.9 (iOS 16.0+)
- **Backend**: Node.js + MongoDB + Cloudflare R2
- **AI**: Claude (Anthropic) + Flux (Fal.ai)
- **Audio**: ElevenLabs + AVSpeechSynthesizer
- **Vitals**: SmartSpectra SDK (Presage Health)
- **Auth**: Auth0

## 🚀 Getting Started

### Prerequisites
- Xcode 15.0+
- iOS 16.0+ device or simulator
- SmartSpectra SDK from Presage Health

### Installation
```bash
git clone https://github.com/yourusername/StoryDrift.git
cd StoryDrift
open Idle.xcodeproj
```

### Configuration
1. **Auth0**: Update domain/clientId in `AuthManager.swift`
2. **Backend**: Set API URL in `APIService.swift` 
3. **SmartSpectra**: Link SDK framework in Xcode
4. **ElevenLabs**: Add API key for premium voices (optional)

## 📱 Usage

### Setup
1. Sign in with Auth0
2. Create child profile (name, age, interests)
3. Set 6-digit parental passcode

### Creating Stories
1. Dashboard → "New Story"
2. Select theme or describe custom story
3. Choose educational level and minigame frequency
4. Position camera for vitals tracking
5. "Start Story"

### Parental Controls
- **Child Mode**: Access to dashboard, stories, journey, settings only
- **Parent Mode**: Full access to all features and analytics
- **PIN Reset**: Use "Forgot passcode?" → Auth0 verification → reset to 000000

## 🔧 Project Structure

```
StoryDrift/
├── Idle/
│   ├── Services/          # Auth, API, Vitals, Audio
│   ├── Views/            # SwiftUI screens
│   ├── Models/           # Data structures
│   └── Components/       # Reusable UI elements
└── StoryDrift-backend/   # Node.js backend
```

## 📝 License

Proprietary - All rights reserved.

---

**Built with ❤️ for better bedtime routines**
