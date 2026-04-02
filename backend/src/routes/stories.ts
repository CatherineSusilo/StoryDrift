import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';
import { StorySession } from '../models/StorySession';
import { z } from 'zod';

const router = Router();

const createStorySchema = z.object({
  childId:           z.string().min(1),
  storyTitle:        z.string().min(1),
  storyContent:      z.string().min(1),
  parentPrompt:      z.string().min(1),
  storytellingTone:  z.enum(['calming', 'energetic', 'sad', 'adventurous', 'none']),
  initialState:      z.enum(['wound-up', 'normal', 'almost-there']),
  initialDriftScore: z.number().int().min(0).max(100),
  imagePrompts:      z.any().optional(),
  generatedImages:   z.array(z.string()).optional(),
  audioUrls:         z.array(z.string()).optional(),
  modelUsed:         z.string().optional(),
  targetDuration:    z.number().int().optional(),
  minigameFrequency: z.string().optional(),
  imageJobId:        z.string().optional(),
  cameraEnabled:     z.boolean().optional(),
});

const updateStorySchema = z.object({
  endTime:           z.string().datetime().optional(),
  duration:          z.number().int().optional(),
  sleepOnsetTime:    z.string().datetime().optional(),
  completed:         z.boolean().optional(),
  finalDriftScore:   z.number().int().min(0).max(100).optional(),
  driftScoreHistory: z.array(z.number().int()).optional(),
});

// ── helper: verify ownership ─────────────────────────────────────────────────

async function getUserChildIds(auth0Id: string): Promise<{ userId: string; childIds: string[] } | null> {
  const user = await User.findOne({ auth0Id });
  if (!user) return null;
  const children = await Child.find({ userId: user._id }).select('_id');
  return { userId: user._id.toString(), childIds: children.map(c => c._id.toString()) };
}

// ── Routes ────────────────────────────────────────────────────────────────────

router.get('/child/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    const { limit = '20', offset = '0' } = req.query;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const ownership = await getUserChildIds(auth0Id);
    if (!ownership) return res.status(404).json({ error: 'User not found' });
    if (!ownership.childIds.includes(childId)) return res.status(404).json({ error: 'Child not found' });

    const lim = parseInt(limit as string);
    const skip = parseInt(offset as string);

    const [stories, total] = await Promise.all([
      StorySession.find({ childId }).sort({ startTime: -1 }).skip(skip).limit(lim),
      StorySession.countDocuments({ childId }),
    ]);

    return res.json({ data: stories.map(s => s.toJSON()), total, limit: lim, offset: skip });
  } catch (error) {
    console.error('Get stories error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get story sessions' });
  }
});

router.get('/vitals/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const ownership = await getUserChildIds(auth0Id);
    if (!ownership) return res.status(404).json({ error: 'User not found' });

    const story = await StorySession.findById(storyId);
    if (!story || !ownership.childIds.includes(story.childId.toString())) {
      return res.status(404).json({ error: 'Story session not found' });
    }
    if (!story.vitals) return res.status(404).json({ error: 'No vitals for this story' });

    return res.json(story.vitals);
  } catch (error) {
    console.error('Get story vitals error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get story vitals' });
  }
});

router.get('/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const ownership = await getUserChildIds(auth0Id);
    if (!ownership) return res.status(404).json({ error: 'User not found' });

    const story = await StorySession.findById(storyId);
    if (!story || !ownership.childIds.includes(story.childId.toString())) {
      return res.status(404).json({ error: 'Story session not found' });
    }

    return res.json(story.toJSON());
  } catch (error) {
    console.error('Get story error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get story session' });
  }
});

router.post('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const ownership = await getUserChildIds(auth0Id);
    if (!ownership) return res.status(404).json({ error: 'User not found' });

    const body = createStorySchema.parse(req.body);
    if (!ownership.childIds.includes(body.childId)) {
      return res.status(404).json({ error: 'Child not found' });
    }

    const story = await StorySession.create({
      childId:           body.childId,
      storyTitle:        body.storyTitle,
      storyContent:      body.storyContent,
      parentPrompt:      body.parentPrompt,
      storytellingTone:  body.storytellingTone,
      initialState:      body.initialState,
      initialDriftScore: body.initialDriftScore,
      imagePrompts:      body.imagePrompts,
      generatedImages:   body.generatedImages ?? [],
      audioUrls:         body.audioUrls ?? [],
      modelUsed:         body.modelUsed,
      targetDuration:    body.targetDuration,
      minigameFrequency: body.minigameFrequency,
      imageJobId:        body.imageJobId,
      cameraEnabled:     body.cameraEnabled,
      driftScoreHistory: [body.initialDriftScore],
    });

    return res.status(201).json(story.toJSON());
  } catch (error) {
    console.error('Create story error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to create story session' });
  }
});

router.patch('/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const ownership = await getUserChildIds(auth0Id);
    if (!ownership) return res.status(404).json({ error: 'User not found' });

    const existing = await StorySession.findById(storyId);
    if (!existing || !ownership.childIds.includes(existing.childId.toString())) {
      return res.status(404).json({ error: 'Story session not found' });
    }

    const body = updateStorySchema.parse(req.body);
    const updateData: any = {};
    if (body.endTime           !== undefined) updateData.endTime           = new Date(body.endTime);
    if (body.duration          !== undefined) updateData.duration          = body.duration;
    if (body.sleepOnsetTime    !== undefined) updateData.sleepOnsetTime    = new Date(body.sleepOnsetTime);
    if (body.completed         !== undefined) updateData.completed         = body.completed;
    if (body.finalDriftScore   !== undefined) updateData.finalDriftScore   = body.finalDriftScore;
    if (body.driftScoreHistory !== undefined) updateData.driftScoreHistory = body.driftScoreHistory;
    if (body.generatedImages   !== undefined) updateData.generatedImages   = body.generatedImages;

    const story = await StorySession.findByIdAndUpdate(storyId, updateData, { new: true });
    return res.json(story!.toJSON());
  } catch (error) {
    console.error('Update story error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to update story session' });
  }
});

router.delete('/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const ownership = await getUserChildIds(auth0Id);
    if (!ownership) return res.status(404).json({ error: 'User not found' });

    const story = await StorySession.findById(storyId);
    if (!story || !ownership.childIds.includes(story.childId.toString())) {
      return res.status(404).json({ error: 'Story session not found' });
    }

    await StorySession.findByIdAndDelete(storyId);
    return res.json({ message: 'Story session deleted successfully' });
  } catch (error) {
    console.error('Delete story error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to delete story session' });
  }
});

// ── Vitals (embedded in StorySession) ────────────────────────────────────────

const storyVitalsSchema = z.object({
  childId:          z.string().min(1),
  avgHeartRate:     z.number().min(0),
  avgBreathingRate: z.number().min(0),
  minHeartRate:     z.number().min(0).optional(),
  maxHeartRate:     z.number().min(0).optional(),
  snapshots:        z.array(z.any()).optional(),
});

router.post('/vitals/:storyId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { storyId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const ownership = await getUserChildIds(auth0Id);
    if (!ownership) return res.status(404).json({ error: 'User not found' });

    const story = await StorySession.findById(storyId);
    if (!story || !ownership.childIds.includes(story.childId.toString())) {
      return res.status(404).json({ error: 'Story session not found' });
    }

    const parsed = storyVitalsSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

    const { avgHeartRate, avgBreathingRate, minHeartRate = 0, maxHeartRate = 0, snapshots = [] } = parsed.data;

    const updated = await StorySession.findByIdAndUpdate(
      storyId,
      {
        avgHeartRate,
        avgBreathingRate,
        vitals: { avgHeartRate, avgBreathingRate, minHeartRate, maxHeartRate, snapshots, updatedAt: new Date() },
      },
      { new: true },
    );

    return res.json(updated!.vitals);
  } catch (error) {
    console.error('Save story vitals error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to save story vitals' });
  }
});

export default router;
