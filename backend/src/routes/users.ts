import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';
import { z } from 'zod';

const router = Router();

router.get('/me', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const children = await Child.find({ userId: user._id }).sort({ createdAt: 1 });
    return res.json({ ...user.toJSON(), children: children.map(c => c.toJSON()) });
  } catch (error) {
    console.error('Get user error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get user profile' });
  }
});

const updateUserSchema = z.object({
  name:    z.string().optional(),
  picture: z.string().optional(),
});

router.patch('/me', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const body = updateUserSchema.parse(req.body);
    const user = await User.findOneAndUpdate({ auth0Id }, body, { new: true });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const children = await Child.find({ userId: user._id }).sort({ createdAt: 1 });
    return res.json({ ...user.toJSON(), children: children.map(c => c.toJSON()) });
  } catch (error) {
    console.error('Update user error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to update user profile' });
  }
});

export default router;
