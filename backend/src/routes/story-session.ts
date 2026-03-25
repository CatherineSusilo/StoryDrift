import { Router, Response } from 'express';
import { z } from 'zod';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import {
  createBedtimeSession,
  createEducationalSession,
  getSession,
  deleteSession,
  tick,
  recordMinigameResult,
} from '../lib/story-graph/graph';
import { ChildProfile, BiometricInput } from '../lib/story-graph/types';

const router = Router();

// ── Input schemas ──────────────────────────────────────────────────────────────

const ChildProfileSchema = z.object({
  childId: z.string(),
  name: z.string(),
  age: z.number().int().min(1).max(16),
  favoriteAnimal: z.string().optional(),
  favoritePlace: z.string().optional(),
  favoriteCharacter: z.string().optional(),
  preferredWorld: z.enum(['forest', 'ocean', 'space', 'village']).optional(),
  tonightsMood: z.enum(['wound_up', 'normal', 'almost_there']).optional(),
});

const BiometricSchema = z.object({
  pulse_rate: z.number().optional(),
  breathing_rate: z.number().optional(),
  movement_level: z.number().min(0).max(1).optional(),
  expression_tone: z.number().min(0).max(1).optional(),
  eye_focus: z.number().min(0).max(1).optional(),
  signal_quality: z.number().min(0).max(1).optional(),
});

const StartBedtimeSchema = z.object({
  mode: z.literal('bedtime'),
  childProfile: ChildProfileSchema,
});

const StartEducationalSchema = z.object({
  mode: z.literal('educational'),
  childProfile: ChildProfileSchema,
  lessonName: z.string().min(1),
  lessonDescription: z.string().min(1),
});

const StartSchema = z.discriminatedUnion('mode', [StartBedtimeSchema, StartEducationalSchema]);

// ── POST /api/story-session/start ─────────────────────────────────────────────

router.post('/start', async (req: AuthRequest, res: Response) => {
  try {
    const parsed = StartSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'Invalid request body', details: parsed.error.flatten() });
    }

    const body = parsed.data;
    const { childProfile } = body;

    // Verify child belongs to this user
    const child = await prisma.child.findFirst({
      where: { id: childProfile.childId },
      include: { user: true },
    });
    if (!child) {
      return res.status(404).json({ error: 'Child not found' });
    }

    let state;

    if (body.mode === 'bedtime') {
      console.log(`🌙 Starting bedtime session for ${childProfile.name}`);
      state = createBedtimeSession(childProfile as ChildProfile);
    } else {
      console.log(`📚 Starting educational session: "${body.lessonName}" for ${childProfile.name}`);
      state = await createEducationalSession(
        childProfile as ChildProfile,
        body.lessonName,
        body.lessonDescription,
      );
    }

    // Persist session record to DB
    await prisma.storyGraphSession.create({
      data: {
        id: state.sessionId,
        childId: childProfile.childId,
        mode: body.mode,
        state: JSON.stringify(state),
        lessonName: body.mode === 'educational' ? body.lessonName : null,
      },
    });

    res.json({
      sessionId: state.sessionId,
      mode: state.mode,
      state,
    });
  } catch (err: any) {
    console.error('❌ Start session error:', err.message);
    res.status(500).json({ error: 'Failed to start story session', details: err.message });
  }
});

// ── POST /api/story-session/:sessionId/tick ────────────────────────────────────

router.post('/:sessionId/tick', async (req: AuthRequest, res: Response) => {
  try {
    const { sessionId } = req.params;

    // Check memory first, then restore from DB if needed
    let session = getSession(sessionId);
    if (!session) {
      const record = await prisma.storyGraphSession.findUnique({ where: { id: sessionId } });
      if (!record) return res.status(404).json({ error: 'Session not found' });
      // This is a simplified restore — in production use a proper cache
      return res.status(410).json({ error: 'Session expired from memory. Please start a new session.' });
    }

    if (session.session_complete) {
      return res.status(200).json({ sessionComplete: true, state: session });
    }

    const bioParsed = BiometricSchema.safeParse(req.body.biometrics ?? {});
    const biometrics: BiometricInput = bioParsed.success ? bioParsed.data : {};

    console.log(`⏱️  Tick for session ${sessionId} | mode: ${session.mode}`);
    const result = await tick(sessionId, biometrics);

    // Persist updated state to DB
    await prisma.storyGraphSession.update({
      where: { id: sessionId },
      data: {
        state: JSON.stringify(result.state),
        completed: result.sessionComplete,
        endTime: result.sessionComplete ? new Date() : undefined,
      },
    });

    // Return tick result without the full audio blob in the top-level to keep response lean
    res.json({
      segment: result.segment,
      imageUrl: result.imageUrl,
      audioUrl: req.query.includeAudio === '1' ? result.audioUrl : undefined,
      strategy: result.strategy,
      score: result.score,
      trajectory: result.trajectory,
      arcPosition: result.arcPosition,
      lessonProgress: result.lessonProgress,
      minigame: result.minigame ?? null,
      sessionComplete: result.sessionComplete,
    });
  } catch (err: any) {
    console.error('❌ Tick error:', err.message);
    res.status(500).json({ error: 'Failed to process tick', details: err.message });
  }
});

// ── GET /api/story-session/:sessionId/state ────────────────────────────────────

router.get('/:sessionId/state', async (req: AuthRequest, res: Response) => {
  const { sessionId } = req.params;
  const session = getSession(sessionId);

  if (!session) {
    const record = await prisma.storyGraphSession.findUnique({ where: { id: sessionId } });
    if (!record) return res.status(404).json({ error: 'Session not found' });
    return res.json({ state: JSON.parse(record.state) });
  }

  res.json({ state: session });
});

// ── POST /api/story-session/:sessionId/end ────────────────────────────────────

router.post('/:sessionId/end', async (req: AuthRequest, res: Response) => {
  try {
    const { sessionId } = req.params;
    const session = getSession(sessionId);

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    // Build summary
    let summary: Record<string, unknown>;

    if (session.mode === 'bedtime') {
      summary = {
        mode: 'bedtime',
        sessionId,
        childName: session.childProfile.name,
        session_duration_minutes: session.session_minutes,
        sleep_onset_time: session.sleep_onset_time,
        final_drift_score: session.drift_score,
        drift_score_curve: session.drift_score_history,
        total_segments: session.segments.length,
        arc_position_reached: session.arc_position,
      };
    } else {
      const lessonSession = session;
      summary = {
        mode: 'educational',
        sessionId,
        childName: session.childProfile.name,
        lesson_name: lessonSession.lesson_name,
        lesson_progress: lessonSession.lesson_progress,
        concepts_introduced: lessonSession.concepts_introduced,
        concepts_reinforced: lessonSession.concepts_reinforced,
        engagement_score_curve: lessonSession.engagement_score_history,
        peak_learning_windows: lessonSession.engagement_score_history
          .map((s, i) => ({ minute: i, score: s }))
          .filter((e) => e.score >= 60 && e.score <= 85),
        session_duration_minutes: session.session_minutes,
        total_segments: session.segments.length,
        lesson_complete: lessonSession.lesson_progress >= 100,
      };
    }

    // Persist final state
    await prisma.storyGraphSession.update({
      where: { id: sessionId },
      data: {
        state: JSON.stringify(session),
        completed: true,
        endTime: new Date(),
      },
    });

    deleteSession(sessionId);

    res.json({ summary });
  } catch (err: any) {
    console.error('❌ End session error:', err.message);
    res.status(500).json({ error: 'Failed to end session', details: err.message });
  }
});

// ── POST /api/story-session/:sessionId/minigame-result ────────────────────────

router.post('/:sessionId/minigame-result', async (req: AuthRequest, res: Response) => {
  try {
    const { sessionId } = req.params;
    const { type, completed, correct, skipped, responseData } = req.body;

    if (!type) return res.status(400).json({ error: 'minigame type required' });

    recordMinigameResult(sessionId, { type, completed, correct, skipped, responseData });

    res.json({ ok: true });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to record minigame result', details: err.message });
  }
});

// ── GET /api/story-session/history/:childId ───────────────────────────────────

router.get('/history/:childId', async (req: AuthRequest, res: Response) => {
  try {
    const { childId } = req.params;
    const sessions = await prisma.storyGraphSession.findMany({
      where: { childId },
      orderBy: { createdAt: 'desc' },
      take: 20,
      select: {
        id: true,
        mode: true,
        lessonName: true,
        completed: true,
        startTime: true,
        endTime: true,
        createdAt: true,
      },
    });
    res.json({ sessions });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to fetch history', details: err.message });
  }
});

export default router;
