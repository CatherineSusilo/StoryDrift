import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';

const router = Router();

// POST /api/vitals/child/:childId
// Accepts live vitals pings from VitalsManager during a story session.
// Stores as the latest live reading on the child record (non-critical, best-effort).
router.post('/child/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;

    if (!auth0Id) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { heartRate, breathingRate, signalQuality, timestamp } = req.body;

    // Verify the child belongs to the authenticated user
    const user = await prisma.user.findUnique({ where: { auth0Id } });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const child = await prisma.child.findFirst({
      where: { id: childId, userId: user.id },
    });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    // Acknowledge the ping — full vitals summary is saved at story end via /api/stories/vitals/:storyId
    res.json({
      ok: true,
      received: { heartRate, breathingRate, signalQuality, timestamp },
    });
  } catch (error) {
    console.error('Live vitals ping error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to process vitals' });
  }
});

export default router;
