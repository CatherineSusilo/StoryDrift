# Minigame Drawings Auto-Save Feature

## Overview

Drawings created by children during educational story minigames are now automatically saved to the drawings collection. This allows parents to see all their child's artwork in one place, and these drawings can later be used to inspire story image generation.

## Implementation Details

### How It Works

1. **During Story Session**:
   - When a child completes a drawing minigame, the drawing is captured as a base64-encoded PNG
   - The drawing is stored in memory along with a timestamp
   - Multiple drawings from the same session are collected

2. **When Story Completes**:
   - All collected drawings are converted to `ChildDrawing` objects
   - Each drawing gets a descriptive name: `🔢 Lesson Name - 2026-03-31_193045`
   - Drawings are saved to UserDefaults (same storage as manually uploaded drawings)
   - Drawings appear immediately in the "drawings collection" view

3. **Early Exit Handling**:
   - If the user exits the story before completion, drawings are still saved
   - This happens in the `tearDown()` function

### Data Flow

```
DrawingMinigame
    ↓
  [Child draws with PencilKit]
    ↓
  PKDrawing → PNG Data → Base64 String
    ↓
  MinigameResult(responseData: base64)
    ↓
EducationalStorySessionView.handleMinigameComplete()
    ↓
  Collect in minigameDrawings array
    ↓
  [Story continues...]
    ↓
  Story completes OR user exits
    ↓
  saveMinigameDrawings()
    ↓
  Convert base64 → PNG Data
    ↓
  Create ChildDrawing objects
    ↓
  Load existing drawings from UserDefaults
    ↓
  Append new drawings
    ↓
  Save back to UserDefaults
    ↓
DrawingsManagerView displays all drawings
```

### Code Changes

#### 1. Models.swift
- **Added**: `ChildDrawing` model (moved from DrawingsManagerView)
- **Why**: Shared data model needed by both EducationalStorySessionView and DrawingsManagerView

```swift
struct ChildDrawing: Codable, Identifiable {
    let id: String
    let name: String
    let imageData: Data
    let uploadedAt: Date
}
```

#### 2. EducationalStorySessionView.swift
- **Added**: `minigameDrawings` state array to track drawings during session
- **Modified**: `handleMinigameComplete()` to collect drawing results
- **Modified**: `applyTickResponse()` to save drawings when story completes
- **Modified**: `tearDown()` to save drawings when story exits early
- **Added**: `saveMinigameDrawings()` function to persist drawings to collection

```swift
// State
@State private var minigameDrawings: [(base64: String, timestamp: Date)] = []

// Collect drawings
if result.type == .drawing, result.completed, let base64 = result.responseData {
    minigameDrawings.append((base64: base64, timestamp: Date()))
}

// Save on completion or exit
saveMinigameDrawings()
```

#### 3. DrawingsManagerView.swift
- **Removed**: `ChildDrawing` model definition (moved to Models.swift)
- **No functional changes**: Still loads/saves drawings the same way

### Storage Format

**UserDefaults Key**: `drawings_{childId}`

**Example**:
```swift
// Key: "drawings_69cb41d8cb7d385f2ecf1f9e"
// Value: JSON array of ChildDrawing objects
[
  {
    "id": "ABC-123",
    "name": "📚 Adding Numbers - 2026-03-31_193045",
    "imageData": <PNG bytes>,
    "uploadedAt": "2026-03-31T19:30:45Z"
  },
  {
    "id": "DEF-456", 
    "name": "🔢 Counting Game - 2026-03-31_194112",
    "imageData": <PNG bytes>,
    "uploadedAt": "2026-03-31T19:41:12Z"
  }
]
```

### Drawing Name Format

Format: `{lesson.emoji} {lesson.name} - {timestamp}`

Examples:
- `📚 Adding Numbers - 2026-03-31_193045`
- `🔤 Letter Recognition - 2026-03-31_194112`
- `🎨 Colors and Shapes - 2026-03-31_195230`

The timestamp uses format: `yyyy-MM-dd_HHmmss` (24-hour time)

### Logging

Console output when drawings are saved:

```
📝 Collected drawing #1 from minigame
📝 Collected drawing #2 from minigame
💾 Saving 2 drawings to collection for child 69cb41d8cb7d385f2ecf1f9e
✅ Added drawing: 📚 Adding Numbers - 2026-03-31_193045
✅ Added drawing: 📚 Adding Numbers - 2026-03-31_193107
💾 Saved 2 new drawings to collection
```

If story exits early:
```
📝 Story ended early - saving 1 drawings
💾 Saving 1 drawings to collection for child 69cb41d8cb7d385f2ecf1f9e
✅ Added drawing: 🔤 Letter Recognition - 2026-03-31_194522
💾 Saved 1 new drawings to collection
```

### User Experience

1. **During Story**:
   - Child encounters drawing minigame
   - Draws a picture using PencilKit canvas
   - Taps "Done"
   - Drawing is silently collected in background
   - Story continues seamlessly

2. **After Story**:
   - Parent opens "drawings collection" from main menu
   - Sees new drawings with lesson names and timestamps
   - Can view, delete, or use drawings for story inspiration

3. **Multiple Drawings**:
   - If minigame frequency is high (e.g., "every_paragraph")
   - Multiple drawings from same story are all saved
   - Each gets unique timestamp
   - All appear in collection

### Technical Notes

#### Image Format
- **Source**: PencilKit `PKDrawing` on pale yellow canvas
- **Encoding**: PNG format via `UIImage.pngData()`
- **Transfer**: Base64 string in `MinigameResult.responseData`
- **Storage**: Raw PNG bytes in `ChildDrawing.imageData`

#### Canvas Background
- Minigame canvas uses pale yellow background: `#FEFF1E0`
- This matches the parchment aesthetic of the app
- Background color is preserved in the PNG

#### Memory Management
- Drawings stored in memory array during session (temporary)
- Converted to persistent storage only at end
- Base64 strings are relatively small (~50-200KB per drawing)
- Multiple drawings per session won't cause memory issues

#### Error Handling
- If base64 decode fails, drawing is skipped with warning log
- If JSON encoding fails, error is logged but app continues
- Individual drawing failures don't prevent saving other drawings

### Testing

To test this feature:

1. **Start Educational Story**:
   ```swift
   // In LessonRoadmapView, select any lesson
   // Choose minigame frequency: "every 3rd" or higher
   ```

2. **Complete Drawing Minigame**:
   - Draw something on the canvas
   - Tap "Done"
   - Watch console for "📝 Collected drawing" message

3. **Complete or Exit Story**:
   - Let story finish OR tap close button
   - Watch console for "💾 Saving X drawings" messages

4. **View in Collection**:
   - Navigate to "drawings collection" from main menu
   - Select child
   - See newly saved drawings with lesson names

5. **Verify Persistence**:
   - Close and reopen app
   - Drawings should still be in collection
   - Can delete drawings normally

### Future Enhancements

Possible improvements:

1. **Cloud Sync**:
   - Upload drawings to backend API
   - Sync across devices
   - Backup and restore

2. **Drawing Preview**:
   - Show thumbnail in story summary
   - "View drawings created" button after story

3. **Sharing**:
   - Share drawings via iOS share sheet
   - Export as PDF or image file

4. **Gallery View**:
   - Filter by lesson/date
   - Slideshow mode
   - Print option

5. **Story Inspiration**:
   - Mark drawings as "favorites"
   - Use specific drawings for next story
   - AI analysis of drawing content

### Compatibility

- **iOS Version**: iOS 16.0+
- **Storage**: UserDefaults (no size limit in practice)
- **Performance**: O(n) where n = number of drawings per child
- **Thread Safety**: All UserDefaults access on main thread

### Troubleshooting

**Drawings not appearing:**
- Check console for error messages
- Verify child ID matches between session and collection
- Check UserDefaults key: `drawings_{childId}`

**"Failed to decode drawing" warning:**
- Base64 string from minigame may be corrupt
- Check DrawingMinigame.submitDrawing() PNG encoding

**"Failed to encode drawings" error:**
- Too many drawings (very unlikely)
- Check available device storage
- Try deleting old drawings

### Known Limitations

1. **Local Storage Only**: Drawings not backed up to cloud (yet)
2. **No Size Limit**: UserDefaults can grow indefinitely
3. **No Compression**: PNG images stored uncompressed
4. **Single Device**: Drawings don't sync between devices

### Conclusion

This feature seamlessly integrates drawing minigames with the existing drawings collection, creating a complete repository of the child's artwork from both uploaded photos and in-story creations. Parents can easily see their child's progress and creative development over time.
