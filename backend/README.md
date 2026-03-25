# StoryDrift Backend API

TypeScript backend with Auth0 authentication, user management, child profiles, sleep tracking, and story session tracking.

## Features

- 🔐 **Auth0 Integration** - Secure JWT authentication
- 👥 **User Management** - User profiles linked to Auth0
- 👶 **Child Profiles** - Multiple children per user with preferences
- 📖 **Story Tracking** - Track story sessions with drift scores
- 😴 **Sleep Tracking** - Comprehensive sleep session logging
- 📊 **Statistics & Insights** - Sleep and story analytics
- 🗄️ **PostgreSQL + Prisma** - Type-safe database access

## Tech Stack

- **TypeScript** - Type-safe development
- **Express** - Web framework
- **Prisma** - Database ORM
- **PostgreSQL** - Database
- **Auth0** - Authentication & authorization
- **Zod** - Runtime validation

## Quick Start

### 1. Install Dependencies

```bash
cd backend
npm install
```

### 2. Configure Database

The project uses **MongoDB Atlas** (cloud-hosted MongoDB). The connection string is already configured in `.env.example`.

### 3. Configure Environment

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

**Required variables:**
- `DATABASE_URL` - MongoDB Atlas connection string (already configured)
- `AUTH0_DOMAIN` - Your Auth0 tenant domain (e.g., `tenant.us.auth0.com`)
- `AUTH0_AUDIENCE` - Your Auth0 API identifier (e.g., `https://api.storydrift.app`)
- `AUTH0_CLIENT_ID` - Auth0 application client ID
- `AUTH0_CLIENT_SECRET` - Auth0 application client secret

**Optional:**
- `GEMINI_API_KEY` - Google Gemini API key (used for story generation and Imagen image generation)
- `FAL_API_KEY` - ~~Fal.ai API key~~ (deprecated - now using Gemini Imagen for images)
- `ELEVENLABS_API_KEY` - ElevenLabs API key for voice synthesis

### 4. Set Up Database

```bash
# Generate Prisma client
npm run prisma:generate

# Push schema to MongoDB (no migrations needed for MongoDB)
npx prisma db push

# (Optional) Open Prisma Studio GUI
npm run prisma:studio
```

### 5. Start Server

```bash
# Development mode (with auto-reload)
npm run dev

# Production mode
npm run build
npm start
```

Server runs on `http://localhost:3001`

### 6. Test API

```bash
# Health check (no auth required)
curl http://localhost:3001/health

# Protected endpoint (requires Auth0 token)
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3001/api/users/me
```

## API Endpoints

### Authentication
- `POST /api/auth/profile` - Get or create user profile (requires Auth0 token)

### Users
- `GET /api/users/me` - Get current user profile
- `PATCH /api/users/me` - Update user profile

### Children
- `GET /api/children` - List all children for current user
- `GET /api/children/:childId` - Get single child
- `POST /api/children` - Create new child
- `PATCH /api/children/:childId` - Update child
- `DELETE /api/children/:childId` - Delete child

### Stories
- `GET /api/stories/child/:childId` - List story sessions for child
- `GET /api/stories/:storyId` - Get single story session
- `POST /api/stories` - Create story session
- `PATCH /api/stories/:storyId` - Update/complete story session
- `DELETE /api/stories/:storyId` - Delete story session

### Sleep
- `GET /api/sleep/child/:childId` - List sleep sessions for child
- `GET /api/sleep/:sleepId` - Get single sleep session
- `POST /api/sleep` - Create sleep session
- `PATCH /api/sleep/:sleepId` - Update sleep session
- `DELETE /api/sleep/:sleepId` - Delete sleep session

### Statistics
- `GET /api/statistics/sleep/:childId` - Get sleep statistics
- `GET /api/statistics/stories/:childId` - Get story statistics
- `GET /api/statistics/insights/:childId` - Get personalized insights

## Database Schema

### User
- Linked to Auth0 via `auth0Id`
- Has multiple children

### Child
- Belongs to a user
- Has preferences (storytelling tone, favorite themes)
- Has many story and sleep sessions

### StorySession
- Tracks individual story playback
- Records drift scores over time
- Links to AI-generated content

### SleepSession
- Tracks sleep metrics
- Can link to a story session
- Records quality, duration, efficiency

### ChildPreferences
- Stores child-specific preferences
- Storytelling tone, themes, default state

## Development

### Run in Development Mode
```bash
npm run dev
```

### Build for Production
```bash
npm run build
npm start
```

### Database Commands
```bash
# Generate Prisma client
npm run prisma:generate

# Create migration
npm run migrate

# Deploy migrations (production)
npm run migrate:deploy

# Open Prisma Studio
npm run prisma:studio
```

## Auth0 Setup

### Create Auth0 Application

1. Go to https://auth0.com and create an account
2. Create a new **Single Page Application**:
   - Copy the **Domain** (e.g., `tenant.us.auth0.com`)
   - Copy the **Client ID**
   - Set **Allowed Callback URLs**: `http://localhost:5173`
   - Set **Allowed Logout URLs**: `http://localhost:5173`
   - Set **Allowed Web Origins**: `http://localhost:5173`

### Create Auth0 API

1. Go to **Applications** → **APIs** → **Create API**
2. Configure:
   - Name: `StoryDrift API`
   - Identifier: `https://api.storydrift.app` (use as `AUTH0_AUDIENCE`)
   - Signing Algorithm: `RS256`
3. Enable RBAC and "Add Permissions in Token"

## Security

- All routes (except `/api/auth`) require valid Auth0 JWT token
- Users can only access their own data and their children's data
- Input validation using Zod schemas
- Helmet.js for security headers
- CORS configured for frontend origin

## Frontend Integration

### Install Auth0 React SDK

```bash
npm install @auth0/auth0-react
```

### Configure Auth0 Provider

```tsx
import { Auth0Provider } from '@auth0/auth0-react';

<Auth0Provider
  domain={import.meta.env.VITE_AUTH0_DOMAIN}
  clientId={import.meta.env.VITE_AUTH0_CLIENT_ID}
  authorizationParams={{
    redirect_uri: window.location.origin,
    audience: "https://api.storydrift.app",
    scope: "openid profile email"
  }}
>
  <App />
</Auth0Provider>
```

### Make API Calls

```typescript
import { useAuth0 } from '@auth0/auth0-react';

const { getAccessTokenSilently } = useAuth0();

const token = await getAccessTokenSilently();

fetch('http://localhost:3001/api/children', {
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  },
});
```

## Example API Requests

### Create a Child

```bash
curl -X POST http://localhost:3001/api/children \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Emma",
    "age": 6,
    "preferences": {
      "storytellingTone": "calming",
      "favoriteThemes": ["forest", "animals"],
      "defaultInitialState": "normal"
    }
  }'
```

### Create Story Session

```bash
curl -X POST http://localhost:3001/api/stories \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "childId": "CHILD_ID",
    "storyTitle": "Emma'\''s Forest Adventure",
    "storyContent": "Once upon a time...",
    "parentPrompt": "A story about a magical forest",
    "storytellingTone": "calming",
    "initialState": "normal",
    "initialDriftScore": 35
  }'
```

### Get Sleep Statistics

```bash
curl "http://localhost:3001/api/statistics/sleep/CHILD_ID?days=30" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Production Deployment

### Deploy Backend
- Use Railway, Render, or AWS
- Set `NODE_ENV=production`
- Run `npm run migrate:deploy`
- Build: `npm run build`
- Start: `npm start`

### Deploy Database
- MongoDB Atlas is already cloud-hosted and production-ready
- No additional database deployment needed

### Update Auth0
- Add production URLs to Allowed Callbacks/Logout URLs
- Update CORS_ORIGIN in backend env

## Troubleshooting

**Port already in use:**
```bash
# Windows
netstat -ano | findstr :3001
taskkill /PID <PID> /F

# Mac/Linux
lsof -ti:3001 | xargs kill -9
```

**Database connection error:**
- Verify MongoDB Atlas connection string in `.env`
- Check network access in MongoDB Atlas dashboard
- Whitelist your IP address in Atlas
- Try: `npx prisma db push`

**Auth0 401 errors:**
- Verify `AUTH0_DOMAIN` and `AUTH0_AUDIENCE` match Auth0 dashboard
- Check token hasn't expired
- Ensure API identifier matches audience in token request

## License

MIT
