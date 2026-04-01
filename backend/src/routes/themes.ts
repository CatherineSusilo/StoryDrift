import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Theme } from '../models/Theme';
import { uploadToR2 } from '../lib/r2';
import { analyseImageWithClaude, detectMimeType } from '../lib/vision';
import { z } from 'zod';

const router = Router();

const createThemeSchema = z.object({
  name:        z.string().min(1).max(100),
  description: z.string().max(300).optional(),
  emoji:       z.string().max(10).optional(),
  imageData:   z.string().optional(),  // base64 image — Claude will analyse and enrich description
});

const updateThemeSchema = createThemeSchema.partial();

// GET /api/themes — all themes for the authenticated user
router.get('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const themes = await Theme.find({ userId: user._id }).sort({ name: 1 });
    return res.json(themes.map(t => t.toJSON()));
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to get themes', details: err.message });
  }
});

// POST /api/themes — create a theme
router.post('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const body = createThemeSchema.parse(req.body);

    let imageUrl: string | undefined;
    let imageDescription: string | undefined;

    if (body.imageData) {
      const buf = Buffer.from(body.imageData, 'base64');
      if (buf.length > 5 * 1024 * 1024) return res.status(400).json({ error: 'Image too large (max 5MB)' });
      const mimeType = detectMimeType(body.imageData);
      const ext = mimeType.split('/')[1];
      imageUrl = await uploadToR2(buf, ext, mimeType);
      console.log(`🔍 Analysing theme image with Claude…`);
      imageDescription = await analyseImageWithClaude(body.imageData, mimeType, `a story theme called "${body.name}"`);
    }

    const theme = await Theme.create({
      userId:           user._id,
      name:             body.name,
      description:      body.description,
      emoji:            body.emoji,
      imageUrl,
      imageDescription,
    });

    return res.status(201).json(theme.toJSON());
  } catch (err: any) {
    if (err.name === 'ZodError') return res.status(400).json({ error: 'Validation failed', details: err.errors });
    res.status(500).json({ error: 'Failed to create theme', details: err.message });
  }
});

// PATCH /api/themes/:themeId — update a theme
router.patch('/:themeId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const body = updateThemeSchema.parse(req.body);
    const theme = await Theme.findOneAndUpdate(
      { _id: req.params.themeId, userId: user._id },
      { $set: body },
      { new: true },
    );
    if (!theme) return res.status(404).json({ error: 'Theme not found' });

    return res.json(theme.toJSON());
  } catch (err: any) {
    if (err.name === 'ZodError') return res.status(400).json({ error: 'Validation failed', details: err.errors });
    res.status(500).json({ error: 'Failed to update theme', details: err.message });
  }
});

// DELETE /api/themes/:themeId — delete a theme
router.delete('/:themeId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const theme = await Theme.findOneAndDelete({ _id: req.params.themeId, userId: user._id });
    if (!theme) return res.status(404).json({ error: 'Theme not found' });

    return res.json({ message: 'Theme deleted', id: req.params.themeId });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to delete theme', details: err.message });
  }
});

export default router;
