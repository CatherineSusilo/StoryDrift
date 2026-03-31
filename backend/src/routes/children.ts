import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';
import { z } from 'zod';

const router = Router();

const createChildSchema = z.object({
  name:        z.string().min(1).max(100),
  age:         z.number().int().min(0).max(18),
  dateOfBirth: z.string().datetime().optional(),
  avatar:      z.string().url().optional(),
  preferences: z.object({
    storytellingTone:    z.enum(['calming', 'energetic', 'sad', 'adventurous', 'none']).default('calming'),
    favoriteThemes:      z.array(z.string()).default([]),
    defaultInitialState: z.enum(['wound-up', 'normal', 'almost-there']).default('normal'),
    personality:         z.string().optional(),
    favoriteMedia:       z.string().optional(),
    parentGoals:         z.string().optional(),
  }).optional(),
});

const updateChildSchema = createChildSchema.partial();

router.get('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const children = await Child.find({ userId: user._id }).sort({ createdAt: 1 });
    return res.json(children.map(c => c.toJSON()));
  } catch (error) {
    console.error('Get children error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get children' });
  }
});

router.get('/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const child = await Child.findOne({ _id: childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    return res.json(child.toJSON());
  } catch (error) {
    console.error('Get child error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get child' });
  }
});

router.post('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const body = createChildSchema.parse(req.body);

    const child = await Child.create({
      userId:      user._id,
      name:        body.name,
      age:         body.age,
      dateOfBirth: body.dateOfBirth ? new Date(body.dateOfBirth) : undefined,
      avatar:      body.avatar,
      preferences: body.preferences ?? null,
    });

    return res.status(201).json(child.toJSON());
  } catch (error) {
    console.error('Create child error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to create child' });
  }
});

router.patch('/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const existing = await Child.findOne({ _id: childId, userId: user._id });
    if (!existing) return res.status(404).json({ error: 'Child not found' });

    const body = updateChildSchema.parse(req.body);
    const updateData: any = {};
    if (body.name        !== undefined) updateData.name        = body.name;
    if (body.age         !== undefined) updateData.age         = body.age;
    if (body.dateOfBirth !== undefined) updateData.dateOfBirth = new Date(body.dateOfBirth);
    if (body.avatar      !== undefined) updateData.avatar      = body.avatar;
    if (body.preferences !== undefined) updateData.preferences = body.preferences;

    const child = await Child.findByIdAndUpdate(childId, updateData, { new: true });
    return res.json(child!.toJSON());
  } catch (error) {
    console.error('Update child error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to update child' });
  }
});

router.delete('/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const child = await Child.findOneAndDelete({ _id: childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    return res.json({ message: 'Child deleted successfully' });
  } catch (error) {
    console.error('Delete child error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to delete child' });
  }
});

export default router;
