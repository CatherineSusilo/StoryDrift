import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import { z } from 'zod';

const router = Router();

// Schema for creating a sleep session
const createSleepSchema = z.object({
  childId: z.string().min(1),
  bedtime: z.string().datetime(),
  wakeupTime: z.string().datetime().optional(),
  quality: z.enum(['poor', 'fair', 'good', 'excellent']).optional(),
  notes: z.string().optional(),
  timeToSleep: z.number().int().optional(),
  nightWakings: z.number().int().default(0),
  sleepEfficiency: z.number().min(0).max(100).optional(),
  weatherCondition: z.string().optional(),
  roomTemperature: z.number().optional(),
  storySessionId: z.string().min(1).optional(),
});

// Schema for updating a sleep session
const updateSleepSchema = createSleepSchema.partial().omit({ childId: true });

// Get all sleep sessions for a child
router.get('/child/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    const { limit = '30', offset = '0' } = req.query;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Verify child belongs to user
    const child = await prisma.child.findFirst({
      where: {
        id: childId,
        userId: user.id,
      },
    });

    if (!child) {
      return res.status(404).json({ error: 'Child not found' });
    }

    const sleepSessions = await prisma.sleepSession.findMany({
      where: { childId },
      orderBy: { bedtime: 'desc' },
      take: parseInt(limit as string),
      skip: parseInt(offset as string),
    });

    const total = await prisma.sleepSession.count({
      where: { childId },
    });

    res.json({
      data: sleepSessions,
      total,
      limit: parseInt(limit as string),
      offset: parseInt(offset as string),
    });
  } catch (error) {
    console.error('Get sleep sessions error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get sleep sessions' });
  }
});

// Get single sleep session
router.get('/:sleepId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { sleepId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const sleepSession = await prisma.sleepSession.findFirst({
      where: {
        id: sleepId,
        child: {
          userId: user.id,
        },
      },
      include: {
        child: true,
      },
    });

    if (!sleepSession) {
      return res.status(404).json({ error: 'Sleep session not found' });
    }

    res.json(sleepSession);
  } catch (error) {
    console.error('Get sleep session error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get sleep session' });
  }
});

// Create a new sleep session
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

    const body = createSleepSchema.parse(req.body);

    // Verify child belongs to user
    const child = await prisma.child.findFirst({
      where: {
        id: body.childId,
        userId: user.id,
      },
    });

    if (!child) {
      return res.status(404).json({ error: 'Child not found' });
    }

    // Calculate duration if wakeup time provided
    let duration: number | undefined;
    if (body.wakeupTime) {
      const bedtime = new Date(body.bedtime);
      const wakeup = new Date(body.wakeupTime);
      duration = Math.floor((wakeup.getTime() - bedtime.getTime()) / 1000 / 60); // minutes
    }

    const sleepSession = await prisma.sleepSession.create({
      data: {
        childId: body.childId,
        bedtime: new Date(body.bedtime),
        wakeupTime: body.wakeupTime ? new Date(body.wakeupTime) : undefined,
        duration,
        quality: body.quality,
        notes: body.notes,
        timeToSleep: body.timeToSleep,
        nightWakings: body.nightWakings,
        sleepEfficiency: body.sleepEfficiency,
        weatherCondition: body.weatherCondition,
        roomTemperature: body.roomTemperature,
        storySessionId: body.storySessionId,
      },
    });

    res.status(201).json(sleepSession);
  } catch (error) {
    console.error('Create sleep session error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to create sleep session' });
  }
});

// Update a sleep session
router.patch('/:sleepId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { sleepId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Verify sleep session belongs to user's child
    const existingSleep = await prisma.sleepSession.findFirst({
      where: {
        id: sleepId,
        child: {
          userId: user.id,
        },
      },
    });

    if (!existingSleep) {
      return res.status(404).json({ error: 'Sleep session not found' });
    }

    const body = updateSleepSchema.parse(req.body);

    // Calculate duration if wakeup time updated
    let duration: number | undefined;
    if (body.wakeupTime || body.bedtime) {
      const bedtime = body.bedtime ? new Date(body.bedtime) : existingSleep.bedtime;
      const wakeup = body.wakeupTime ? new Date(body.wakeupTime) : existingSleep.wakeupTime;
      if (wakeup) {
        duration = Math.floor((wakeup.getTime() - bedtime.getTime()) / 1000 / 60);
      }
    }

    const sleepSession = await prisma.sleepSession.update({
      where: { id: sleepId },
      data: {
        bedtime: body.bedtime ? new Date(body.bedtime) : undefined,
        wakeupTime: body.wakeupTime ? new Date(body.wakeupTime) : undefined,
        duration,
        quality: body.quality,
        notes: body.notes,
        timeToSleep: body.timeToSleep,
        nightWakings: body.nightWakings,
        sleepEfficiency: body.sleepEfficiency,
        weatherCondition: body.weatherCondition,
        roomTemperature: body.roomTemperature,
      },
    });

    res.json(sleepSession);
  } catch (error) {
    console.error('Update sleep session error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to update sleep session' });
  }
});

// Delete a sleep session
router.delete('/:sleepId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { sleepId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { auth0Id },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Verify sleep session belongs to user's child
    const existingSleep = await prisma.sleepSession.findFirst({
      where: {
        id: sleepId,
        child: {
          userId: user.id,
        },
      },
    });

    if (!existingSleep) {
      return res.status(404).json({ error: 'Sleep session not found' });
    }

    await prisma.sleepSession.delete({
      where: { id: sleepId },
    });

    res.json({ message: 'Sleep session deleted successfully' });
  } catch (error) {
    console.error('Delete sleep session error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to delete sleep session' });
  }
});

export default router;
