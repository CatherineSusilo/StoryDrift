# MongoDB Drawings Sync Documentation

## Overview

All drawings from the drawings collection are now automatically synced to MongoDB, providing cloud backup and enabling future cross-device synchronization.

## Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     iOS App (Local)                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Drawing Created:                                           │
│  • Minigame drawing during story                            │
│  • Manual photo upload                                      │
│          ↓                                                  │
│  Save to UserDefaults                                       │
│  • Key: drawings_{childId}                                  │
│  • Format: JSON array of ChildDrawing                       │
│  • synchronize() for immediate persistence                  │
│          ↓                                                  │
│  Automatic Background Sync to MongoDB                       │
│  • Task { await syncDrawingsToBackend() }                   │
│  • Batch upload API for efficiency                          │
│  • Continues even if network unavailable                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                         ↓ HTTP POST
┌─────────────────────────────────────────────────────────────┐
│                  Backend API (Node.js)                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  POST /api/drawings/batch                                   │
│  • Validates auth token (Auth0)                             │
│  • Verifies child ownership                                 │
│  • Decodes base64 image data                                │
│  • Validates image size (<5MB)                              │
│  • Stores in MongoDB                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                   MongoDB Database                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Collection: drawings                                       │
│  • userId: ObjectId (indexed)                               │
│  • childId: ObjectId (indexed)                              │
│  • name: String                                             │
│  • imageData: Buffer (binary PNG)                           │
│  • uploadedAt: Date                                         │
│  • source: 'manual_upload' | 'minigame'                     │
│  • lessonName: String? (for minigames)                      │
│  • lessonEmoji: String? (for minigames)                     │
│  • createdAt, updatedAt: Date                               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Backend Implementation

### MongoDB Model (`backend/src/models/Drawing.ts`)

```typescript
interface IDrawing {
  userId: ObjectId;
  childId: ObjectId;
  name: string;
  imageData: Buffer;        // Binary PNG data
  uploadedAt: Date;
  source: 'manual_upload' | 'minigame';
  lessonName?: string;
  lessonEmoji?: string;
  createdAt: Date;
  updatedAt: Date;
}
```

**Features:**
- Binary storage for efficiency (vs base64 string)
- Indexed by userId and childId for fast queries
- Source tracking to distinguish manual uploads from minigames
- Lesson metadata preserved for minigame drawings
- Automatic timestamps

### API Endpoints (`backend/src/routes/drawings.ts`)

#### 1. GET /api/drawings/child/:childId
Get all drawings for a child.

**Response:**
```json
[
  {
    "id": "507f1f77bcf86cd799439011",
    "childId": "507f191e810c19729de860ea",
    "name": "📚 Adding Numbers - 2026-03-31_193045",
    "imageData": "iVBORw0KGgoAAAANSUhEUgAAA...", 
    "uploadedAt": "2026-03-31T19:30:45.000Z",
    "source": "minigame",
    "lessonName": "Adding Numbers",
    "lessonEmoji": "📚",
    "createdAt": "2026-03-31T19:30:50.000Z",
    "updatedAt": "2026-03-31T19:30:50.000Z"
  }
]
```

#### 2. POST /api/drawings
Upload a single drawing.

**Request:**
```json
{
  "childId": "507f191e810c19729de860ea",
  "name": "My Drawing",
  "imageData": "iVBORw0KGgoAAAANSUhEUgAAA...",
  "uploadedAt": "2026-03-31T19:30:45.000Z",
  "source": "manual_upload"
}
```

**Response:** Drawing object (same as GET)

#### 3. POST /api/drawings/batch
Bulk upload multiple drawings (for syncing).

**Request:**
```json
{
  "childId": "507f191e810c19729de860ea",
  "drawings": [
    {
      "childId": "507f191e810c19729de860ea",
      "name": "Drawing 1",
      "imageData": "iVBORw0KGgoAAAANSUhEUgAAA...",
      "uploadedAt": "2026-03-31T19:30:45.000Z",
      "source": "minigame",
      "lessonName": "Adding Numbers",
      "lessonEmoji": "📚"
    },
    {
      "childId": "507f191e810c19729de860ea",
      "name": "Drawing 2",
      "imageData": "iVBORw0KGgoAAAANSUhEUgAAA...",
      "uploadedAt": "2026-03-31T19:35:22.000Z",
      "source": "manual_upload"
    }
  ]
}
```

**Response:**
```json
{
  "message": "Uploaded 2 drawings",
  "success": 2,
  "failed": 0,
  "errors": null
}
```

#### 4. DELETE /api/drawings/:drawingId
Delete a drawing.

**Response:**
```json
{
  "message": "Drawing deleted",
  "id": "507f1f77bcf86cd799439011"
}
```

### Security

- All endpoints require Auth0 authentication
- Child ownership verified for every operation
- User can only access/modify their own children's drawings
- Image size limited to 5MB per drawing

## iOS Implementation

### API Service Methods (`Idle/Services/APIService.swift`)

```swift
// Fetch all drawings for a child
func getDrawings(childId: String, token: String) async throws -> [DrawingResponse]

// Upload single drawing
func uploadDrawing(drawing: DrawingUploadRequest, token: String) async throws -> DrawingResponse

// Batch upload (for syncing)
func uploadDrawingsBatch(childId: String, drawings: [DrawingUploadRequest], token: String) 
    async throws -> DrawingBatchResponse

// Delete drawing
func deleteDrawing(drawingId: String, token: String) async throws
```

### Models

```swift
struct DrawingResponse: Codable, Identifiable {
    let id: String
    let childId: String
    let name: String
    let imageData: String  // base64
    let uploadedAt: Date
    let source: String
    let lessonName: String?
    let lessonEmoji: String?
    let createdAt: Date
    let updatedAt: Date
}

struct DrawingUploadRequest: Codable {
    let childId: String
    let name: String
    let imageData: String  // base64
    let uploadedAt: Date
    let source: String
    let lessonName: String?
    let lessonEmoji: String?
}
```

### Automatic Sync Implementation

#### DrawingsManagerView
```swift
private func saveDrawings(childId: String) {
    // 1. Save to UserDefaults
    let data = try JSONEncoder().encode(drawings)
    UserDefaults.standard.set(data, forKey: drawingsKey(childId: childId))
    UserDefaults.standard.synchronize()
    
    // 2. Sync to MongoDB in background
    Task {
        await syncDrawingsToBackend(childId: childId)
    }
}
```

Called when:
- User uploads new photos
- User deletes a drawing
- Any modification to the collection

#### EducationalStorySessionView
```swift
@MainActor
private func saveMinigameDrawings() {
    // 1. Save to UserDefaults (existing code)
    // ...
    
    // 2. Sync to MongoDB
    Task {
        await syncMinigameDrawingsToBackend(
            drawings: Array(existingDrawings.suffix(minigameDrawings.count))
        )
    }
}
```

Called when:
- Story completes successfully
- Story exited early (tearDown)

### Background Sync

Sync happens asynchronously without blocking UI:
```swift
Task {
    await syncDrawingsToBackend(childId: childId)
}
```

**Benefits:**
- Non-blocking UI
- Retries on network errors (TODO)
- Silent failures don't disrupt user experience
- Continues even if user navigates away

## Console Logging

### When Syncing

```
☁️ Syncing 3 drawings to MongoDB...
✅ MongoDB sync complete: 3 uploaded, 0 failed
```

### When Sync Fails

```
☁️ Syncing 3 drawings to MongoDB...
❌ MongoDB sync failed: The Internet connection appears to be offline.
```

### When Some Drawings Fail

```
☁️ Syncing 3 drawings to MongoDB...
✅ MongoDB sync complete: 2 uploaded, 1 failed
⚠️ Sync errors: Drawing 3: Image too large
```

### When No Auth Token

```
⚠️ No auth token - skipping backend sync
```

## Usage Flow

### Scenario 1: Minigame Drawing

1. **Child completes drawing minigame**
   - Drawing captured as base64 PNG
   - Stored in `minigameDrawings` array

2. **Story completes**
   - `saveMinigameDrawings()` called
   - Drawing saved to UserDefaults
   - Background sync to MongoDB starts
   - Console: `☁️ Syncing 1 drawings to MongoDB...`

3. **Sync completes**
   - Console: `✅ MongoDB sync complete: 1 uploaded, 0 failed`
   - Drawing now in cloud

### Scenario 2: Manual Photo Upload

1. **User taps "upload drawing" button**
   - PhotosPicker shown
   - User selects 3 photos

2. **Photos processed**
   - Converted to PNG Data
   - Added to `drawings` array
   - `saveDrawings()` called

3. **Save sequence**
   - Saved to UserDefaults
   - Console: `✅ Drawings saved and synchronized to UserDefaults`
   - Background sync starts
   - Console: `☁️ Syncing 5 drawings to MongoDB...` (3 new + 2 existing)

4. **Sync completes**
   - Console: `✅ MongoDB sync complete: 3 uploaded, 2 failed`
   - Console: `⚠️ Sync errors: Drawing 4: Already exists, Drawing 5: Already exists`
   - New drawings in cloud, duplicates skipped

### Scenario 3: Delete Drawing

1. **User taps delete on drawing**
   - Confirmation alert shown
   - User confirms

2. **Delete sequence**
   - Removed from `drawings` array
   - `saveDrawings()` called
   - UserDefaults updated
   - `deleteDrawingFromBackend()` called

3. **Backend delete**
   - Console: `✅ Drawing deleted from backend: 507f1f77bcf86cd799439011`
   - Drawing removed from MongoDB

## Error Handling

### Network Failures

If network is unavailable during sync:
- Error logged: `❌ MongoDB sync failed: The Internet connection appears to be offline.`
- Drawing remains in UserDefaults
- Will sync on next save (when network returns)

**TODO:** Implement automatic retry mechanism

### Auth Failures

If auth token expired:
- Sync skipped: `⚠️ No auth token - skipping backend sync`
- User needs to re-login
- Drawings safe in UserDefaults

### Individual Drawing Failures

If one drawing in batch fails:
- Other drawings still uploaded
- Failure logged with specific error
- Successful count still reported

### Image Size Limits

Backend rejects images > 5MB:
- Error: `Image too large (max 5MB)`
- Other drawings in batch still processed
- User should compress large images

## Storage Considerations

### MongoDB Storage

- **Binary Format**: PNG stored as Buffer (efficient)
- **Average Size**: 50-200KB per drawing
- **Estimated Capacity**: 
  - 1GB storage ≈ 5,000-20,000 drawings
  - Typical child: 50-200 drawings
  - System can handle 25-200 children per GB

### Local Storage (UserDefaults)

- **Same Format**: PNG Data
- **iOS Limit**: ~4MB per key (40-50 drawings)
- **Solution**: Paginate or use file system if needed

### Compression Options (Future)

Consider adding:
- Server-side PNG compression
- JPEG conversion for photos (smaller)
- Image resizing (max 2000x2000 px)

## Testing

### Manual Test Flow

1. **Test Minigame Sync**
   ```
   - Start educational story
   - Complete drawing minigame
   - Complete story
   - Check console for sync logs
   - Verify drawing in MongoDB (use MongoDB Compass)
   ```

2. **Test Manual Upload Sync**
   ```
   - Open drawings collection
   - Upload photo from Photos app
   - Check console for sync logs
   - Verify in MongoDB
   ```

3. **Test Delete Sync**
   ```
   - Delete a drawing
   - Check console for delete log
   - Verify removed from MongoDB
   ```

4. **Test Network Failure**
   ```
   - Turn off WiFi
   - Add drawing
   - Check console: "skipping backend sync" or network error
   - Turn on WiFi
   - Add another drawing
   - Both should sync
   ```

### MongoDB Verification

Using MongoDB Compass:
```
1. Connect to: mongodb://localhost:27017 (or your MongoDB URI)
2. Database: storydrift (or your DB name)
3. Collection: drawings
4. Find drawings: { childId: ObjectId("...") }
5. Verify imageData is binary BSON type
6. Check source, lessonName, lessonEmoji fields
```

Using Mongo Shell:
```javascript
// Count drawings for a child
db.drawings.countDocuments({ childId: ObjectId("507f191e810c19729de860ea") })

// Find all minigame drawings
db.drawings.find({ source: "minigame" })

// Check drawing size
db.drawings.find().forEach(d => print(d.name + ": " + d.imageData.length + " bytes"))

// Find drawings by lesson
db.drawings.find({ lessonName: "Adding Numbers" })
```

## Future Enhancements

### 1. Pull from Cloud
Currently only pushes to MongoDB. Add:
```swift
func pullDrawingsFromBackend(childId: String) async {
    // Fetch from MongoDB
    // Merge with local UserDefaults
    // Resolve conflicts (last-write-wins)
}
```

### 2. Conflict Resolution
When same drawing edited on multiple devices:
- Use `updatedAt` timestamp
- Last write wins
- Or: keep both versions with suffix

### 3. Selective Sync
Only sync changed drawings:
- Add `synced: Bool` flag to ChildDrawing
- Track `lastSyncDate` in UserDefaults
- Only upload unsynced drawings

### 4. Image Optimization
Before upload:
- Resize large images (>2000px)
- Compress PNG (pngquant)
- Convert photos to JPEG with quality 85%

### 5. Offline Queue
Robust offline support:
- Queue failed uploads
- Retry with exponential backoff
- Persist queue to disk

### 6. Cross-Device Sync
Enable true sync across devices:
- Periodic background fetch
- Push notifications on new drawings
- Conflict resolution strategy

### 7. Deletion Tracking
Handle edge cases:
- Drawing deleted on Device A
- Not yet synced to Device B
- Need deletion tombstones

## Monitoring

### Backend Logs

```bash
# Watch for drawing uploads
tail -f /tmp/backend.log | grep "drawings"

# Count drawings in MongoDB
mongo storydrift --eval "db.drawings.countDocuments({})"

# Check recent uploads
mongo storydrift --eval "db.drawings.find().sort({createdAt:-1}).limit(5)"
```

### iOS Debug

```swift
// In Xcode console
po UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("drawings_") }

// Check sync status
po authManager.accessToken != nil  // Can sync?
```

## Security & Privacy

### Data Protection

- ✅ Auth0 authentication required
- ✅ Child ownership verified
- ✅ User isolation (can't access others' drawings)
- ✅ HTTPS in production
- ✅ Token-based auth (no passwords in requests)

### Privacy Considerations

- Drawings contain children's artwork (potentially sensitive)
- Binary storage (can't be easily viewed in DB logs)
- No drawing content analysis (fully private)
- Parents control all data

### GDPR Compliance

To add:
- Data export endpoint (download all drawings)
- Data deletion endpoint (delete all user data)
- Privacy policy acknowledgment

## Troubleshooting

### "No auth token - skipping backend sync"

**Cause:** User not logged in or token expired  
**Fix:** User needs to log in again

### "MongoDB sync failed: 401 Unauthorized"

**Cause:** Auth token invalid/expired  
**Fix:** Log out and log in again

### "Image too large (max 5MB)"

**Cause:** Drawing image exceeds size limit  
**Fix:** Compress image or reduce quality before upload

### Drawings not appearing in MongoDB

**Check:**
1. Backend running? `curl http://localhost:3001/health`
2. Console shows sync logs?
3. Auth token valid?
4. MongoDB connected? Check backend startup logs
5. Collection exists? `db.drawings.find().count()`

### Sync seems slow

**Causes:**
- Uploading many large images
- Slow network connection
- Server processing time

**Solutions:**
- Compress images before upload
- Batch API already optimized
- Consider background queue with progress tracking

## Conclusion

All drawings are now automatically backed up to MongoDB, providing:
- ✅ Data persistence beyond local device
- ✅ Foundation for cross-device sync
- ✅ Protection against data loss
- ✅ Scalable storage solution
- ✅ Rich metadata tracking (source, lesson info)
- ✅ Efficient binary storage

The system gracefully handles:
- Network failures (logs but doesn't crash)
- Auth issues (skips sync silently)
- Individual upload failures (continues batch)
- Large images (rejects with clear error)

Next steps: Add pull sync and conflict resolution for true multi-device support!
