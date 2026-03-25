import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import { z } from 'zod';

const router = Router();

// Helper: deserialize a ChildPreferences object (favoriteThemes stored as JSON string)
function deserializePreferences(prefs: any) {
  if (!prefs) return prefs;
  return {
    ...prefs,
    favoriteThemes: JSON.parse(prefs.favoriteThemes || '[]'),
  };
}

// Helper: deserialize child (includes preferences)
function deserializeChild(child: any) {
  if (!child) return child;
  return {
    ...child,
    preferences: child.preferences ? deserializePreferences(child.preferences) : child.preferences,
  };
}

// Schema for creating a child
const createChildSchema = z.object({
  name: z.string().min(1).max(100),
  age: z.number().int().min(0).max(18),
  dateOfBirth: z.string().datetime().optional(),
  avatar: z.string().url().optional(),
  preferences: z.object({
    storytellingTone: z.enum(['calming', 'energetic', 'sad', 'adventurous', 'none']).default('calming'),
    favoriteThemes: z.array(z.string()).default([]),
    defaultInitialState: z.enum(['wound-up', 'normal', 'almost-there']).default('normal'),
  }).optional(),
});

// Schema for updating a child
const updateChildSchema = createChildSchema.partial();

// Get all children for current user
router.get('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const children = await prisma.child.findMany({
      where: { userId: user.id },
      include: {
        preferences: true,
      },
      orderBy: { createdAt: 'asc' },
    });

    res.json(children.map(deserializeChild));
  } catch (error) {
    console.error('Get children error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get children' });
  }
});

// Get single child
router.get('/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const child = await prisma.child.findFirst({
      where: {
        id: childId,
        userId: user.id,
      },
      include: {
        preferences: true,
      },
    });

    if (!child) {
      return res.status(404).json({ error: 'Child not found' });
    }

    res.json(deserializeChild(child));
  } catch (error) {
    console.error('Get child error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get child' });
  }
});

// Create a new child
router.post('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const body = createChildSchema.parse(req.body);

    const child = await prisma.child.create({
      data: {
        userId: user.id,
        name: body.name,
        age: body.age,
        dateOfBirth: body.dateOfBirth ? new Date(body.dateOfBirth) : undefined,
        avatar: body.avatar,
        preferences: body.preferences ? {
          create: {
            ...body.preferences,
            favoriteThemes: JSON.stringify(body.preferences.favoriteThemes),
          },
        } : undefined,
      },
      include: {
        preferences: true,
      },
    });

    res.status(201).json(deserializeChild(child));
  } catch (error) {
    console.error('Create child error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to create child' });
  }
});

// Update a child
router.patch('/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check child belongs to user
    const existingChild = await prisma.child.findFirst({
      where: {
        id: childId,
        userId: user.id,
      },
    });

    if (!existingChild) {
      return res.status(404).json({ error: 'Child not found' });
    }

    const body = updateChildSchema.parse(req.body);

    const child = await prisma.child.update({
      where: { id: childId },
      data: {
        name: body.name,
        age: body.age,
        dateOfBirth: body.dateOfBirth ? new Date(body.dateOfBirth) : undefined,
        avatar: body.avatar,
        preferences: body.preferences ? {
          upsert: {
            create: {
              ...body.preferences,
              favoriteThemes: JSON.stringify(body.preferences.favoriteThemes ?? []),
            },
            update: {
              ...body.preferences,
              favoriteThemes: JSON.stringify(body.preferences.favoriteThemes ?? []),
            },
          },
        } : undefined,
      },
      include: {
        preferences: true,
      },
    });

    res.json(deserializeChild(child));
  } catch (error) {
    console.error('Update child error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to update child' });
  }
});

// Delete a child
router.delete('/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check child belongs to user
    const existingChild = await prisma.child.findFirst({
      where: {
        id: childId,
        userId: user.id,
      },
    });

    if (!existingChild) {
      return res.status(404).json({ error: 'Child not found' });
    }

    await prisma.child.delete({
      where: { id: childId },
    });

    res.json({ message: 'Child deleted successfully' });
  } catch (error) {
    console.error('Delete child error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to delete child' });
  }
});

export default router;
