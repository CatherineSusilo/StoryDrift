import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

// IMPORTANT: Load environment variables FIRST before importing auth middleware
dotenv.config();

// Ensure story image/audio uploads directory exists
const uploadsDir = path.join(process.cwd(), 'uploads', 'story-images');
if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

import { connectDB } from './lib/db';
import { authMiddleware } from './middleware/auth';
import { errorHandler } from './middleware/errorHandler';
import { requestLogger } from './middleware/requestLogger';

// Routes
import authRoutes from './routes/auth';
import userRoutes from './routes/users';
import childrenRoutes from './routes/children';
import storyRoutes from './routes/stories';
import sleepRoutes from './routes/sleep';
import statisticsRoutes from './routes/statistics';
import audioRoutes from './routes/audio';
import generateRoutes from './routes/generate';
import vitalsRoutes from './routes/vitals';
import storySessionRoutes from './routes/story-session';
import drawingsRoutes from './routes/drawings';

const app = express();
const PORT = parseInt(process.env.PORT || '3001', 10);

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:5173',
  credentials: true,
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(requestLogger);

// ── Static: story images + audio (no auth required) ──────────────────────────
// Served at GET /images/{filename} — matches the /images/xxx.mp3 and /images/xxx.png URLs
// stored in MongoDB. Files are immutable so we cache them for a year client-side.
app.use('/images', express.static(uploadsDir, { maxAge: '365d', immutable: true }));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Public routes (no auth required)
app.use('/api/auth', authRoutes);

// Protected routes (require Auth0 token)
app.use('/api/users', authMiddleware, userRoutes);
app.use('/api/children', authMiddleware, childrenRoutes);
app.use('/api/stories', authMiddleware, storyRoutes);
app.use('/api/sleep', authMiddleware, sleepRoutes);
app.use('/api/statistics', authMiddleware, statisticsRoutes);
app.use('/api/audio', authMiddleware, audioRoutes);
app.use('/api/generate', authMiddleware, generateRoutes);
app.use('/api/vitals', authMiddleware, vitalsRoutes);
app.use('/api/story-session', authMiddleware, storySessionRoutes);
app.use('/api/drawings', authMiddleware, drawingsRoutes);

// Error handling
app.use(errorHandler);

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

let server: ReturnType<typeof app.listen>;

connectDB()
  .then(() => {
    server = app.listen(PORT, '0.0.0.0', () => {
      console.log(`🚀 StoryDrift API running on http://0.0.0.0:${PORT}`);
      console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
      console.log(`🔐 Auth0 Domain: ${process.env.AUTH0_DOMAIN}`);
    });
  })
  .catch(err => {
    console.error('❌ Failed to connect to MongoDB:', err.message);
    process.exit(1);
  });

const shutdown = () => {
  if (server) server.close(() => process.exit(0));
  else process.exit(0);
  setTimeout(() => process.exit(1), 3000);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

export default app;
