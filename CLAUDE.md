# CLAUDE.md — StoryDrift

iOS bedtime story app (SwiftUI) + Node.js backend (Express + MongoDB).

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
- **AI**: Claude via **Backboard.io relay** — all Claude calls go through `claudeChat()` in `src/lib/backboard.ts` (never `new Anthropic()` directly elsewhere). Backboard runs `claude-haiku-4-5-20251001` for everything (story, title, minigame, character profile). See **Backboard relay** below.
- **Images**: fal.ai — every paragraph is independent text-to-image. Flux Schnell (standard) / Flux Dev (premium tier). No img2img.
- **Audio**: ElevenLabs TTS (direct, not relayed)
- **Storage**: Cloudflare R2 via `uploadToR2`

### Backboard relay (Claude)
Direct Anthropic credit is exhausted; Backboard wraps Claude. All Claude/text calls route through `claudeChat(params)` (`src/lib/backboard.ts`), a drop-in for `claude.messages.create`.
- Endpoint `POST {BACKBOARD_BASE_URL}/threads/messages`, header `X-API-Key`, body `{content, llm_provider:'anthropic', model_name:'claude-haiku-4-5-20251001'}`. Base URL `https://app.backboard.io/api`.
- Backboard returns upstream LLM failures as **HTTP 200 + `"LLM Error: …"`** content — `claudeChat` detects and throws.
- `content` is **text only** — Backboard can't do vision. When relaying, image-analysis calls (`analyseImageWithClaude`, `analyseImageShort`, `describeDrawings`) are skipped and return `""`.
- Flag `DISABLE_BACKBOARD`: `true` → direct Anthropic API (needs credit, restores vision); `false` → Backboard. Env: `BACKBOARD_API_KEY`, `BACKBOARD_BASE_URL`.

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
Every paragraph is an **independent text-to-image** render (no img2img — feeding the
previous image back made each image echo the last one). `generateParagraphImage`:
- `quality: 'standard'` → `fal-ai/flux/schnell` (4 steps); `'premium'` → `fal-ai/flux/dev` (28 steps, future subscription tier).
- Style consistency comes from a shared art-style string: the parent's `imageStyle` (AI Customization → image generation style) is the primary directive (~60%), selected character appearance is secondary (~40%).
- `FAL_SAFETY_SUFFIX` (child-safety + format guardrails) is **always appended — never remove it**. `DEFAULT_ART_STYLE` is used when no `imageStyle` is provided.

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
    "characters": ["Luna the fox (a gentle fox; curious; small orange fox)"],
    "drawingPrompts": ["<base64 png>"],
    "imageStyle": "soft watercolor",
    "imageQuality": "standard"
  }
}
```
`characters` are prompt fragments from the iOS local `CharacterStore` (`promptFragment` = name + description + traits + optional hidden 1-sentence image analysis). Response includes `storyTitle` (Claude Haiku-generated, 3–5 words).

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
