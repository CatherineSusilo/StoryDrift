import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';

const router = Router();

// POST /api/vitals/child/:childId
// Accepts live vitals pings from VitalsManager during a story session (best-effort).
router.post('/child/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const { heartRate, breathingRate, signalQuality, timestamp } = req.body;

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const child = await Child.findOne({ _id: childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    // Acknowledge the ping — full vitals summary is saved at story end via /api/stories/vitals/:storyId
    return res.json({ ok: true, received: { heartRate, breathingRate, signalQuality, timestamp } });
  } catch (error) {
    console.error('Live vitals ping error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to process vitals' });
  }
});

export default router;
