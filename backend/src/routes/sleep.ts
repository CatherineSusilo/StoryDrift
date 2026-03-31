import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';
import { SleepSession } from '../models/SleepSession';
import { z } from 'zod';

const router = Router();

const createSleepSchema = z.object({
  childId:          z.string().min(1),
  bedtime:          z.string().datetime(),
  wakeupTime:       z.string().datetime().optional(),
  quality:          z.enum(['poor', 'fair', 'good', 'excellent']).optional(),
  notes:            z.string().optional(),
  timeToSleep:      z.number().int().optional(),
  nightWakings:     z.number().int().default(0),
  sleepEfficiency:  z.number().min(0).max(100).optional(),
  weatherCondition: z.string().optional(),
  roomTemperature:  z.number().optional(),
  storySessionId:   z.string().min(1).optional(),
});

const updateSleepSchema = createSleepSchema.partial().omit({ childId: true });

async function verifyChildOwnership(auth0Id: string, childId: string) {
  const user = await User.findOne({ auth0Id });
  if (!user) return null;
  const child = await Child.findOne({ _id: childId, userId: user._id });
  return child ? user : null;
}

router.get('/child/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    const { limit = '30', offset = '0' } = req.query;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await verifyChildOwnership(auth0Id, childId);
    if (!user) return res.status(404).json({ error: 'Child not found' });

    const lim  = parseInt(limit as string);
    const skip = parseInt(offset as string);

    const [sessions, total] = await Promise.all([
      SleepSession.find({ childId }).sort({ bedtime: -1 }).skip(skip).limit(lim),
      SleepSession.countDocuments({ childId }),
    ]);

    return res.json({ data: sessions.map(s => s.toJSON()), total, limit: lim, offset: skip });
  } catch (error) {
    console.error('Get sleep sessions error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get sleep sessions' });
  }
});

router.get('/:sleepId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { sleepId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const session = await SleepSession.findById(sleepId);
    if (!session) return res.status(404).json({ error: 'Sleep session not found' });

    const child = await Child.findOne({ _id: session.childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Sleep session not found' });

    return res.json(session.toJSON());
  } catch (error) {
    console.error('Get sleep session error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get sleep session' });
  }
});

router.post('/', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const body = createSleepSchema.parse(req.body);
    const user = await verifyChildOwnership(auth0Id, body.childId);
    if (!user) return res.status(404).json({ error: 'Child not found' });

    let duration: number | undefined;
    if (body.wakeupTime) {
      duration = Math.floor((new Date(body.wakeupTime).getTime() - new Date(body.bedtime).getTime()) / 60000);
    }

    const session = await SleepSession.create({
      childId:          body.childId,
      bedtime:          new Date(body.bedtime),
      wakeupTime:       body.wakeupTime ? new Date(body.wakeupTime) : undefined,
      duration,
      quality:          body.quality,
      notes:            body.notes,
      timeToSleep:      body.timeToSleep,
      nightWakings:     body.nightWakings,
      sleepEfficiency:  body.sleepEfficiency,
      weatherCondition: body.weatherCondition,
      roomTemperature:  body.roomTemperature,
      storySessionId:   body.storySessionId,
    });

    return res.status(201).json(session.toJSON());
  } catch (error) {
    console.error('Create sleep session error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to create sleep session' });
  }
});

router.patch('/:sleepId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { sleepId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const existing = await SleepSession.findById(sleepId);
    if (!existing) return res.status(404).json({ error: 'Sleep session not found' });

    const child = await Child.findOne({ _id: existing.childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Sleep session not found' });

    const body = updateSleepSchema.parse(req.body);
    const updateData: any = {};
    if (body.bedtime          !== undefined) updateData.bedtime          = new Date(body.bedtime);
    if (body.wakeupTime       !== undefined) updateData.wakeupTime       = new Date(body.wakeupTime);
    if (body.quality          !== undefined) updateData.quality          = body.quality;
    if (body.notes            !== undefined) updateData.notes            = body.notes;
    if (body.timeToSleep      !== undefined) updateData.timeToSleep      = body.timeToSleep;
    if (body.nightWakings     !== undefined) updateData.nightWakings     = body.nightWakings;
    if (body.sleepEfficiency  !== undefined) updateData.sleepEfficiency  = body.sleepEfficiency;
    if (body.weatherCondition !== undefined) updateData.weatherCondition = body.weatherCondition;
    if (body.roomTemperature  !== undefined) updateData.roomTemperature  = body.roomTemperature;

    // Recalculate duration if time bounds changed
    const bedtime  = updateData.bedtime  ?? existing.bedtime;
    const wakeup   = updateData.wakeupTime ?? existing.wakeupTime;
    if (wakeup) updateData.duration = Math.floor((wakeup.getTime() - bedtime.getTime()) / 60000);

    const session = await SleepSession.findByIdAndUpdate(sleepId, updateData, { new: true });
    return res.json(session!.toJSON());
  } catch (error) {
    console.error('Update sleep session error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to update sleep session' });
  }
});

router.delete('/:sleepId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { sleepId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const session = await SleepSession.findById(sleepId);
    if (!session) return res.status(404).json({ error: 'Sleep session not found' });

    const child = await Child.findOne({ _id: session.childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Sleep session not found' });

    await SleepSession.findByIdAndDelete(sleepId);
    return res.json({ message: 'Sleep session deleted successfully' });
  } catch (error) {
    console.error('Delete sleep session error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to delete sleep session' });
  }
});

export default router;
