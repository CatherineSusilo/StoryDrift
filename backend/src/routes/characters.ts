import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';
import { Character } from '../models/Character';
import { uploadToR2, deleteFromR2 } from '../lib/r2';
import { analyseImageWithClaude, detectMimeType } from '../lib/vision';
import {
  generateCharacterProfile,
  generateCharacterReferenceImage,
} from '../lib/story-graph/nodes/character-generator';
import { z } from 'zod';

const router = Router();

const createCharacterSchema = z.object({
  childId:      z.string(),
  name:         z.string().min(1).max(100),
  description:  z.string().max(500).optional(),   // if omitted, AI-generated
  temperament:  z.string().max(500).optional(),   // if omitted, AI-generated
  imageData:    z.string().optional(),            // base64 PNG — if omitted, AI-generated
});

const updateCharacterSchema = z.object({
  name:        z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
  temperament: z.string().max(500).optional(),
});

async function verifyChildOwnership(auth0Id: string, childId: string) {
  const user = await User.findOne({ auth0Id });
  if (!user) return { user: null, child: null };
  const child = await Child.findOne({ _id: childId, userId: user._id });
  return { user, child };
}

// GET /api/characters/child/:childId
router.get('/child/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const { user, child } = await verifyChildOwnership(auth0Id, req.params.childId);
    if (!user) return res.status(404).json({ error: 'User not found' });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    const characters = await Character.find({ childId: req.params.childId }).sort({ name: 1 });
    return res.json(characters.map(c => c.toJSON()));
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to get characters', details: err.message });
  }
});

// POST /api/characters — create character (AI-generates profile + image if not supplied)
router.post('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const body = createCharacterSchema.parse(req.body);
    const { user, child } = await verifyChildOwnership(auth0Id, body.childId);
    if (!user) return res.status(404).json({ error: 'User not found' });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    // Generate profile if not provided
    let description = body.description ?? '';
    let temperament = body.temperament ?? '';
    if (!description || !temperament) {
      console.log(`🎭 Generating profile for character "${body.name}"…`);
      const profile = await generateCharacterProfile(body.name, '', child.age);
      if (!description) description = profile.description;
      if (!temperament) temperament = profile.temperament;
    }

    // Generate or upload reference image
    let imageUrl = '';
    let falImageUrl = '';
    let imageDescription = '';
    if (body.imageData) {
      // Caller supplied a base64 image — upload to R2 and analyse with Claude
      const buf = Buffer.from(body.imageData, 'base64');
      if (buf.length > 5 * 1024 * 1024) return res.status(400).json({ error: 'Image too large (max 5MB)' });
      const mimeType = detectMimeType(body.imageData);
      const ext = mimeType.split('/')[1];
      imageUrl = await uploadToR2(buf, ext, mimeType);
      console.log(`🔍 Analysing character image with Claude…`);
      imageDescription = await analyseImageWithClaude(
        body.imageData, mimeType,
        `a story character named "${body.name}" — ${description}`,
      );
    } else {
      console.log(`🎨 Generating reference image for character "${body.name}"…`);
      const generated = await generateCharacterReferenceImage(body.name, description, temperament);
      imageUrl         = generated.imageUrl;
      falImageUrl      = generated.falImageUrl;
    }

    const character = await Character.create({
      childId:     body.childId,
      userId:      user._id,
      name:        body.name,
      description,
      temperament,
      imageUrl,
      falImageUrl,
      imageDescription,
    });

    return res.status(201).json(character.toJSON());
  } catch (err: any) {
    if (err.name === 'ZodError') return res.status(400).json({ error: 'Validation failed', details: err.errors });
    console.error('Create character error:', err.message);
    res.status(500).json({ error: 'Failed to create character', details: err.message });
  }
});

// PATCH /api/characters/:characterId — update name/description/temperament
router.patch('/:characterId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const body = updateCharacterSchema.parse(req.body);
    const character = await Character.findOneAndUpdate(
      { _id: req.params.characterId, userId: user._id },
      { $set: body },
      { new: true },
    );
    if (!character) return res.status(404).json({ error: 'Character not found' });

    return res.json(character.toJSON());
  } catch (err: any) {
    if (err.name === 'ZodError') return res.status(400).json({ error: 'Validation failed', details: err.errors });
    res.status(500).json({ error: 'Failed to update character', details: err.message });
  }
});

// DELETE /api/characters/:characterId
router.delete('/:characterId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const character = await Character.findOneAndDelete({ _id: req.params.characterId, userId: user._id });
    if (!character) return res.status(404).json({ error: 'Character not found' });

    // Delete reference image from R2
    if (character.imageUrl) {
      try { await deleteFromR2(character.imageUrl); } catch {}
    }

    return res.json({ message: 'Character deleted', id: req.params.characterId });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to delete character', details: err.message });
  }
});

export default router;
