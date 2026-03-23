import { Router } from 'express';
import { authMiddleware, AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import { z } from 'zod';

const router = Router();

// Schema for user profile
const userProfileSchema = z.object({
  email: z.string().email(),
  name: z.string().optional(),
  picture: z.string().url().optional(),
});

// Get or create user profile (called after Auth0 login)
router.post('/profile', authMiddleware, async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const body = userProfileSchema.parse(req.body);

    // Find or create user
    let user = await prisma.user.findUnique({
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
      // Create new user
      user = await prisma.user.create({
        data: {
          auth0Id,
          email: body.email,
          name: body.name,
          picture: body.picture,
        },
        include: {
          children: {
            include: {
              preferences: true,
            },
          },
        },
      });
    } else {
      // Update existing user profile
      user = await prisma.user.update({
        where: { auth0Id },
        data: {
          name: body.name,
          picture: body.picture,
        },
        include: {
          children: {
            include: {
              preferences: true,
            },
          },
        },
      });
    }

    res.json(user);
  } catch (error) {
    console.error('Profile error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get/create profile' });
  }
});

export default router;
