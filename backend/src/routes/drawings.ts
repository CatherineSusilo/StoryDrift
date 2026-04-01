import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';
import { Drawing } from '../models/Drawing';
import { uploadToR2, deleteFromR2 } from '../lib/r2';
import { z } from 'zod';

const router = Router();

// Validation schemas
const createDrawingSchema = z.object({
  childId: z.string(),
  name: z.string().min(1).max(200),
  imageData: z.string(),  // base64 encoded PNG
  uploadedAt: z.string().datetime().optional(),
  source: z.enum(['manual_upload', 'minigame']).optional(),
  lessonName: z.string().optional(),
  lessonEmoji: z.string().optional(),
});

const updateDrawingSchema = z.object({
  name: z.string().min(1).max(200).optional(),
});

// Helper to verify child ownership
async function verifyChildOwnership(auth0Id: string, childId: string) {
  const user = await User.findOne({ auth0Id });
  if (!user) return null;
  return Child.findOne({ _id: childId, userId: user._id });
}

// GET /api/drawings/child/:childId - Get all drawings for a child
router.get('/child/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const child = await verifyChildOwnership(auth0Id, childId);
    if (!child) return res.status(404).json({ error: 'Child not found' });

    const drawings = await Drawing.find({ childId })
      .sort({ uploadedAt: -1 });

    return res.json(drawings.map(d => d.toJSON()));
  } catch (error) {
    console.error('Get drawings error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get drawings' });
  }
});

// POST /api/drawings - Create/upload a drawing
router.post('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const body = createDrawingSchema.parse(req.body);

    // Verify child ownership
    const child = await Child.findOne({ _id: body.childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    // Decode base64 image data
    const imageBuffer = Buffer.from(body.imageData, 'base64');

    // Validate it's reasonable size (max 5MB)
    if (imageBuffer.length > 5 * 1024 * 1024) {
      return res.status(400).json({ error: 'Image too large (max 5MB)' });
    }

    // Upload to R2
    const imageUrl = await uploadToR2(imageBuffer, 'png', 'image/png');

    const drawing = await Drawing.create({
      userId: user._id,
      childId: body.childId,
      name: body.name,
      imageUrl,
      uploadedAt: body.uploadedAt ? new Date(body.uploadedAt) : new Date(),
      source: body.source || 'manual_upload',
      lessonName: body.lessonName,
      lessonEmoji: body.lessonEmoji,
    });

    return res.status(201).json(drawing.toJSON());
  } catch (error) {
    if (error instanceof z.ZodError) {
      return res.status(400).json({ error: 'Validation failed', details: error.errors });
    }
    console.error('Create drawing error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to create drawing' });
  }
});

// POST /api/drawings/batch - Bulk upload drawings (for syncing from local storage)
router.post('/batch', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const { childId, drawings } = req.body;

    if (!childId || !Array.isArray(drawings)) {
      return res.status(400).json({ error: 'childId and drawings array required' });
    }

    // Verify child ownership
    const child = await Child.findOne({ _id: childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    // Process each drawing
    const results = {
      success: 0,
      failed: 0,
      errors: [] as string[],
    };

    for (const drawingData of drawings) {
      try {
        const validated = createDrawingSchema.parse({ ...drawingData, childId });
        const imageBuffer = Buffer.from(validated.imageData, 'base64');

        if (imageBuffer.length > 5 * 1024 * 1024) {
          results.failed++;
          results.errors.push(`${validated.name}: Image too large`);
          continue;
        }

        const imageUrl = await uploadToR2(imageBuffer, 'png', 'image/png');

        await Drawing.create({
          userId: user._id,
          childId: validated.childId,
          name: validated.name,
          imageUrl,
          uploadedAt: validated.uploadedAt ? new Date(validated.uploadedAt) : new Date(),
          source: validated.source || 'manual_upload',
          lessonName: validated.lessonName,
          lessonEmoji: validated.lessonEmoji,
        });

        results.success++;
      } catch (error) {
        results.failed++;
        results.errors.push(`${drawingData.name || 'Unknown'}: ${error instanceof Error ? error.message : 'Failed'}`);
      }
    }

    return res.status(200).json({
      message: `Uploaded ${results.success} drawings`,
      success: results.success,
      failed: results.failed,
      errors: results.errors.length > 0 ? results.errors : undefined,
    });
  } catch (error) {
    console.error('Batch upload error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to upload drawings' });
  }
});

// PATCH /api/drawings/:drawingId - Update drawing name
router.patch('/:drawingId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { drawingId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const body = updateDrawingSchema.parse(req.body);

    // Find drawing and verify ownership
    const drawing = await Drawing.findOne({ _id: drawingId, userId: user._id });
    if (!drawing) return res.status(404).json({ error: 'Drawing not found' });

    if (body.name) drawing.name = body.name;
    await drawing.save();

    return res.json(drawing.toJSON());
  } catch (error) {
    if (error instanceof z.ZodError) {
      return res.status(400).json({ error: 'Validation failed', details: error.errors });
    }
    console.error('Update drawing error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to update drawing' });
  }
});

// DELETE /api/drawings/:drawingId - Delete a drawing
router.delete('/:drawingId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { drawingId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const drawing = await Drawing.findOneAndDelete({ _id: drawingId, userId: user._id });
    if (!drawing) return res.status(404).json({ error: 'Drawing not found' });

    // Delete from R2
    try {
      await deleteFromR2(drawing.imageUrl);
    } catch (err: any) {
      console.warn(`⚠️ Failed to delete drawing from R2: ${err.message}`);
    }

    return res.json({ message: 'Drawing deleted', id: drawingId });
  } catch (error) {
    console.error('Delete drawing error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to delete drawing' });
  }
});

export default router;
