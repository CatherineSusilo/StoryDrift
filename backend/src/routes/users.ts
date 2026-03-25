import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import { z } from 'zod';

const router = Router();

// Get current user profile
router.get('/me', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
      include: {
        children: {
          include: {
            preferences: true,
          },
        },
      },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(user);
  } catch (error) {
    console.error('Get user error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get user profile' });
  }
});

// Update user profile
const updateUserSchema = z.object({
  name: z.string().optional(),
  picture: z.string().url().optional(),
});

router.patch('/me', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const body = updateUserSchema.parse(req.body);

    const user = await prisma.user.update({
      where: { auth0Id },
      data: body,
      include: {
        children: {
          include: {
            preferences: true,
          },
        },
      },
    });

    res.json(user);
  } catch (error) {
    console.error('Update user error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to update user profile' });
  }
});

export default router;
