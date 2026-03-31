import { Router } from 'express';
import { authMiddleware, AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';
import { z } from 'zod';

const router = Router();

const userProfileSchema = z.object({
  email:   z.string().optional(),
  name:    z.string().optional(),
  picture: z.string().optional(),
});

// Get or create user profile (called after Auth0 login)
router.post('/profile', authMiddleware, async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const body = userProfileSchema.parse(req.body);

    let user = await User.findOne({ auth0Id });

    if (!user) {
      const email = body.email?.trim()
        ? body.email.trim()
        : `${auth0Id.replace('|', '_')}@storydrift.local`;

      user = await User.create({ auth0Id, email, name: body.name, picture: body.picture });
    } else {
      const updateData: any = {};
      if (body.name    !== undefined) updateData.name    = body.name;
      if (body.picture !== undefined) updateData.picture = body.picture;
      if (body.email?.trim() && user.email.endsWith('@storydrift.local')) {
        updateData.email = body.email.trim();
      }
      if (Object.keys(updateData).length > 0) {
        user = await User.findByIdAndUpdate(user._id, updateData, { new: true }) ?? user;
      }
    }

    const children = await Child.find({ userId: user._id }).sort({ createdAt: 1 });
    return res.json({ ...user.toJSON(), children: children.map(c => c.toJSON()) });
  } catch (error) {
    console.error('Profile error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get/create profile', detail: error instanceof Error ? error.message : String(error) });
  }
});

export default router;
