import { Router } from 'express';
import { authMiddleware, AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import { z } from 'zod';

const router = Router();

// Schema for user profile — email is optional here; only required when creating a new user
const userProfileSchema = z.object({
  email: z.string().optional(),
  name: z.string().optional(),
  picture: z.string().optional(), // Don't validate as URL — Auth0 can return various formats
});

// Get or create user profile (called after Auth0 login)
router.post('/profile', authMiddleware, async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const body = userProfileSchema.parse(req.body);

    // Try to find existing user first
    const includeChildren = {
      children: {
        include: {
          preferences: true,
        },
      },
    };

    let user = await prisma.user.findUnique({
      where: { auth0Id },
      include: includeChildren,
    });

    if (!user) {
      // Need an email to create a new user — derive it from the JWT sub if not provided
      const email = (body.email && body.email.trim() !== '')
        ? body.email
        : `${auth0Id.replace('|', '_')}@storydrift.local`;

      user = await prisma.user.create({
        data: {
          auth0Id,
          email,
          name: body.name,
          picture: body.picture,
        },
        include: includeChildren,
      });
    } else {
      // Update name/picture if provided, and email if a real one is now available
      const updateData: any = {};
      if (body.name !== undefined) updateData.name = body.name;
      if (body.picture !== undefined) updateData.picture = body.picture;
      // Update email if a real one is provided and the stored one looks like a fallback
      if (body.email && body.email.trim() !== '' && user.email.endsWith('@storydrift.local')) {
        updateData.email = body.email.trim();
      }

      if (Object.keys(updateData).length > 0) {
        user = await prisma.user.update({
          where: { auth0Id },
          data: updateData,
          include: includeChildren,
        });
      }
    }

    res.json(user);
  } catch (error) {
    console.error('Profile error (full):', error);
    console.error('Profile error message:', error instanceof Error ? error.message : String(error));
    console.error('Profile error stack:', error instanceof Error ? error.stack : 'no stack');
    res.status(500).json({ error: 'Failed to get/create profile', detail: error instanceof Error ? error.message : String(error) });
  }
});

export default router;
