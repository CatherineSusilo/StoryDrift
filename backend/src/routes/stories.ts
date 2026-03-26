import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import { z } from 'zod';

const router = Router();

// Helper: deserialize a StorySession (arrays stored as JSON strings)
function deserializeStory(story: any) {
  if (!story) return story;
  return {
    ...story,
    driftScoreHistory: JSON.parse(story.driftScoreHistory || '[]'),
    generatedImages: JSON.parse(story.generatedImages || '[]'),
    imagePrompts: story.imagePrompts ? JSON.parse(story.imagePrompts) : null,
  };
}

// Schema for creating a story session
const createStorySchema = z.object({
  childId: z.string().min(1),
  storyTitle: z.string().min(1),
  storyContent: z.string().min(1),
  parentPrompt: z.string().min(1),
  storytellingTone: z.enum(['calming', 'energetic', 'sad', 'adventurous', 'none']),
  initialState: z.enum(['wound-up', 'normal', 'almost-there']),
  initialDriftScore: z.number().int().min(0).max(100),
  imagePrompts: z.any().optional(),
  generatedImages: z.array(z.string()).optional(),
  modelUsed: z.string().optional(),
});

// Schema for updating/completing a story session
const updateStorySchema = z.object({
  endTime: z.string().datetime().optional(),
  duration: z.number().int().optional(),
  sleepOnsetTime: z.string().datetime().optional(),
  completed: z.boolean().optional(),
  finalDriftScore: z.number().int().min(0).max(100).optional(),
  driftScoreHistory: z.array(z.number().int()).optional(),
});

// Get all story sessions for a child
router.get('/child/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    const { limit = '20', offset = '0' } = req.query;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Verify child belongs to user
    const child = await prisma.child.findFirst({
      where: {
        id: childId,
        userId: user.id,
      },
    });

    if (!child) {
      return res.status(404).json({ error: 'Child not found' });
    }

    const stories = await prisma.storySession.findMany({
      where: { childId },
      orderBy: { startTime: 'desc' },
      take: parseInt(limit as string),
      skip: parseInt(offset as string),
    });

    const total = await prisma.storySession.count({
      where: { childId },
    });

    res.json({
      data: stories.map(deserializeStory),
      total,
      limit: parseInt(limit as string),
      offset: parseInt(offset as string),
    });
  } catch (error) {
    console.error('Get stories error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get story sessions' });
  }
});

// Get single story session
router.get('/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const story = await prisma.storySession.findFirst({
      where: {
        id: storyId,
        child: {
          userId: user.id,
        },
      },
      include: {
        child: true,
      },
    });

    if (!story) {
      return res.status(404).json({ error: 'Story session not found' });
    }

    res.json(deserializeStory(story));
  } catch (error) {
    console.error('Get story error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get story session' });
  }
});

// Create a new story session
router.post('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const body = createStorySchema.parse(req.body);

    // Verify child belongs to user
    const child = await prisma.child.findFirst({
      where: {
        id: body.childId,
        userId: user.id,
      },
    });

    if (!child) {
      return res.status(404).json({ error: 'Child not found' });
    }

    const story = await prisma.storySession.create({
      data: {
        childId: body.childId,
        storyTitle: body.storyTitle,
        storyContent: body.storyContent,
        parentPrompt: body.parentPrompt,
        storytellingTone: body.storytellingTone,
        initialState: body.initialState,
        initialDriftScore: body.initialDriftScore,
        imagePrompts: body.imagePrompts ? JSON.stringify(body.imagePrompts) : undefined,
        generatedImages: JSON.stringify(body.generatedImages || []),
        modelUsed: body.modelUsed,
        driftScoreHistory: JSON.stringify([body.initialDriftScore]),
      },
    });

    res.status(201).json(deserializeStory(story));
  } catch (error) {
    console.error('Create story error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to create story session' });
  }
});

// Update/complete a story session
router.patch('/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Verify story belongs to user's child
    const existingStory = await prisma.storySession.findFirst({
      where: {
        id: storyId,
        child: {
          userId: user.id,
        },
      },
    });

    if (!existingStory) {
      return res.status(404).json({ error: 'Story session not found' });
    }

    const body = updateStorySchema.parse(req.body);

    const story = await prisma.storySession.update({
      where: { id: storyId },
      data: {
        endTime: body.endTime ? new Date(body.endTime) : undefined,
        duration: body.duration,
        sleepOnsetTime: body.sleepOnsetTime ? new Date(body.sleepOnsetTime) : undefined,
        completed: body.completed,
        finalDriftScore: body.finalDriftScore,
        driftScoreHistory: body.driftScoreHistory !== undefined ? JSON.stringify(body.driftScoreHistory) : undefined,
      },
    });

    res.json(deserializeStory(story));
  } catch (error) {
    console.error('Update story error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to update story session' });
  }
});

// Delete a story session
router.delete('/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Verify story belongs to user's child
    const existingStory = await prisma.storySession.findFirst({
      where: {
        id: storyId,
        child: {
          userId: user.id,
        },
      },
    });

    if (!existingStory) {
      return res.status(404).json({ error: 'Story session not found' });
    }

    await prisma.storySession.delete({
      where: { id: storyId },
    });

    res.json({ message: 'Story session deleted successfully' });
  } catch (error) {
    console.error('Delete story error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to delete story session' });
  }
});

// ── SmartSpectra Vitals ──────────────────────────────────────────────────────

const storyVitalsSchema = z.object({
  childId: z.string().min(1),
  avgHeartRate: z.number().min(0),
  avgBreathingRate: z.number().min(0),
  minHeartRate: z.number().min(0).optional(),
  maxHeartRate: z.number().min(0).optional(),
  snapshots: z.array(z.any()).optional(),
});

// POST /api/stories/vitals/:storyId — upsert vitals summary for a story session
router.post('/vitals/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;

    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await prisma.user.findUnique({ where: { auth0Id } });
    if (!user) return res.status(404).json({ error: 'User not found' });

    // Verify story belongs to user's child
    const story = await prisma.storySession.findFirst({
      where: { id: storyId, child: { userId: user.id } },
    });
    if (!story) return res.status(404).json({ error: 'Story session not found' });

    const parsed = storyVitalsSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

    const { childId, avgHeartRate, avgBreathingRate, minHeartRate = 0, maxHeartRate = 0, snapshots = [] } = parsed.data;

    const vitals = await prisma.storyVitals.upsert({
      where: { storySessionId: storyId },
      create: {
        storySessionId: storyId,
        childId,
        avgHeartRate,
        avgBreathingRate,
        minHeartRate,
        maxHeartRate,
        snapshots: JSON.stringify(snapshots),
      },
      update: {
        avgHeartRate,
        avgBreathingRate,
        minHeartRate,
        maxHeartRate,
        snapshots: JSON.stringify(snapshots),
      },
    });

    // Also update summary fields on the StorySession itself
    await prisma.storySession.update({
      where: { id: storyId },
      data: { avgHeartRate, avgBreathingRate },
    });

    res.json({ ...vitals, snapshots });
  } catch (error) {
    console.error('Save story vitals error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to save story vitals' });
  }
});

// GET /api/stories/vitals/:storyId — retrieve vitals summary for a story session
router.get('/vitals/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;

    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await prisma.user.findUnique({ where: { auth0Id } });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const story = await prisma.storySession.findFirst({
      where: { id: storyId, child: { userId: user.id } },
      include: { storyVitals: true },
    });
    if (!story) return res.status(404).json({ error: 'Story session not found' });
    if (!story.storyVitals) return res.status(404).json({ error: 'No vitals for this story' });

    const { storyVitals: sv } = story;
    res.json({ ...sv, snapshots: JSON.parse(sv.snapshots || '[]') });
  } catch (error) {
    console.error('Get story vitals error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get story vitals' });
  }
});

export default router;
