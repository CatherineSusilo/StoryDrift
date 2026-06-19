# CLAUDE.md — StoryDrift

iOS bedtime story app (SwiftUI) + Node.js backend (Express + MongoDB).

---

## Pending: R2 custom-domain migration

`R2_PUBLIC_URL` currently `https://pub-aff6b46117274911897b0d0b32ca2d60.r2.dev` — DNS-blocked by some ISPs (confirmed XL Axiata, Indonesia → hijacked to block page). Backend uploads still work (S3 API hostname differs); only client-side GETs fail → AVAudioPlayer falls back to native TTS, images render black.

**Verified on iPad via VPN** — story audio + images load fine, so APIs and pipeline are healthy.

**Migration (do when ready, before global launch):**
1. Cloudflare → R2 → bucket `storydrift` → Settings → Custom Domains → connect `cdn.storydrift.app`.
2. Wait for SSL active. Verify with `curl -I https://cdn.storydrift.app/<key>.mp3`.
3. Set `R2_PUBLIC_URL=https://cdn.storydrift.app` in backend `.env`.
4. Run `OLD_R2_PUBLIC_URL=https://pub-aff6b46117274911897b0d0b32ca2d60.r2.dev npx tsx scripts/migrate-r2-urls.ts --dry-run` then re-run without `--dry-run`.
5. Restart backend. New uploads auto-use new domain (uploadToR2 reads env).

Migration script covers `StorySession.audioUrls` + `generatedImages` only. Extend to `Character.imageUrl`, `Character.inspirationUrl`, and any other R2-URL fields before running if those collections have legacy data.

---

## Repos

| Repo | Path |
|------|------|
| iOS app | `/Users/catherinesusilo/StoryDrift` |
| Backend | `/Users/catherinesusilo/StoryDrift/Idle/StoryDrift-backend` |

---

## iOS Stack

- **Language**: Swift 5.9+, SwiftUI
- **Target**: iOS 17+
- **Auth**: Auth0 via `AuthManager` (`EnvironmentObject`)
- **API**: `APIService.shared` — all network calls, base URL from `APIService.baseURL`
- **Tokens**: stored in `UserDefaults` (`accessToken`, `refreshToken`)

### Key files

| File | Purpose |
|------|---------|
| `Idle/Services/APIService.swift` | All API calls (generate, save, rename, delete story) |
| `Idle/Services/EyeTrackingManager.swift` | Singleton; ARKit (Face ID) + Vision fallback eye tracking; PERCLOS → `driftScore` (0–100) |
| `Idle/Models/Models.swift` | `Story`, `Child`, `ChildProfile`, `AuthUser`, etc. |
| `Idle/Managers/ParentalGateManager.swift` | Singleton; `isParentMode: Bool` gates parent-only UI |
| `Idle/Views/StoryArchiveView.swift` | Archive list, swipe-delete, rename sheet |
| `Idle/Views/ChildDashboardView.swift` | Dashboard stats + recent stories |
| `Idle/Utils/Theme.swift` | Design tokens (`Theme.ink`, `Theme.card`, `Theme.accent`, etc.) |

### Auth pattern
```swift
let token = authManager.accessToken ?? UserDefaults.standard.string(forKey: "accessToken")
```

### Parent-only UI
Check `ParentalGateManager.shared.isParentMode` before rendering parent controls (rename pencil, delete swipe). Never use `@StateObject private var gateManager = ParentalGateManager.shared` — use `.shared` directly or pass `isParentMode` as a `let`.

---

## Backend Stack

- **Runtime**: Node.js + TypeScript
- **Framework**: Express
- **DB**: MongoDB via Mongoose (`StorySession`, `Child`, `User` models)
- **AI**: Anthropic Claude API (`claude-sonnet-4-5` for story, `claude-haiku-4-5-20251001` for title/minigame/drawing description)
- **Images**: fal.ai — Flux Schnell (para 1 text-to-image), Flux Dev (para 2+ image-to-image)
- **Audio**: ElevenLabs TTS
- **Storage**: Cloudflare R2 via `uploadToR2`

### Key routes

| Route | File | Purpose |
|-------|------|---------|
| `POST /api/generate/story` | `routes/generate.ts` | Generate story text + audio + images (background) |
| `GET /api/generate/story-images/:jobId` | `routes/generate.ts` | Poll background image progress |
| `GET /api/stories/child/:childId` | `routes/stories.ts` | List all stories (no 30-day filter) |
| `POST /api/stories` | `routes/stories.ts` | Save completed story |
| `PATCH /api/stories/:storyId` | `routes/stories.ts` | Update (endTime, duration, completed, storyTitle, etc.) |
| `DELETE /api/stories/:storyId` | `routes/stories.ts` | Hard delete, ownership-verified |

### Image generation pipeline
1. Para 1: Flux Schnell text-to-image → sets `firstFalUrl` (style anchor)
2. Para 2: Flux Dev img2img with `firstFalUrl` (strength 0.80)
3. Para 3+: Flux Dev img2img with `prevFalUrl` + strength scales with drift (0.75–0.88)

`FAL_STYLE_SUFFIX` includes child-safety guardrails — never remove them.

### Story generation request shape
```json
{
  "profile": {
    "childId": "...",
    "name": "...",
    "age": 5,
    "storytellingTone": "calming",
    "parentPrompt": "...",
    "initialState": "normal",
    "targetDuration": 15,
    "characters": ["Luna the fox", "Pip the rabbit"],
    "drawingPrompts": ["<base64 png>"]
  }
}
```
Response includes `storyTitle` (Claude Haiku-generated, 3–5 words).

---

## Story flow (iOS)

1. `StorySetupView` — parent configures profile, characters, drawings → `StoryConfig`
2. `APIService.generateStory(config:token:)` — calls `/api/generate/story`, gets text + audio + `imageJobId` + `storyTitle`
3. Story plays; on end/exit → `APIService.saveStory(...)` with `storyTitle`
4. `StoryArchiveView` — parent can rename (pencil icon) or delete (swipe left)

---

## Dashboard stats

Computed client-side from all loaded stories — **do not use the `/statistics` endpoint** (30-day filter, broken avgDuration).

```swift
let withDuration = allBedtimeStories.filter { $0.completed && ($0.duration ?? 0) > 0 }
avgSleepSeconds = withDuration.reduce(0) { $0 + ($1.duration ?? 0) } / withDuration.count
```

---

## Conventions

- `"use client"` equivalent in SwiftUI: add `@State`/`@StateObject` only in views that own state
- Layouts use `Theme.*` tokens — never hardcode colors
- `StorySession` filters to `storytellingTone != "educational"` for bedtime-only views
- Story title default fallback: `"Bedtime Story"` (used when Claude title generation fails)
