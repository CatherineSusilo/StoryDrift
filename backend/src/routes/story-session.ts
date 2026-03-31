import { Router, Response } from 'express';
import { z } from 'zod';
import { AuthRequest } from '../middleware/auth';
import { Child } from '../models/Child';
import { StoryGraphSession } from '../models/StoryGraphSession';
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

const ChildProfileSchema = z.object({
  childId:           z.string(),
  name:              z.string(),
  age:               z.number().int().min(1).max(16),
  favoriteAnimal:    z.string().optional(),
  favoritePlace:     z.string().optional(),
  favoriteCharacter: z.string().optional(),
  preferredWorld:    z.enum(['forest', 'ocean', 'space', 'village']).optional(),
  tonightsMood:      z.enum(['wound_up', 'normal', 'almost_there']).optional(),
});

const BiometricSchema = z.object({
  pulse_rate:      z.number().optional(),
  breathing_rate:  z.number().optional(),
  movement_level:  z.number().min(0).max(1).optional(),
  expression_tone: z.number().min(0).max(1).optional(),
  eye_focus:       z.number().min(0).max(1).optional(),
  signal_quality:  z.number().min(0).max(1).optional(),
});

const StartSchema = z.discriminatedUnion('mode', [
  z.object({
    mode:         z.literal('bedtime'),
    childProfile: ChildProfileSchema,
  }),
  z.object({
    mode:               z.literal('educational'),
    childProfile:       ChildProfileSchema,
    lessonName:         z.string().min(1),
    lessonDescription:  z.string().min(1),
    minigameFrequency:  z.enum(['none', 'every_5th', 'every_3rd', 'every_paragraph']).optional(),
  }),
]);

// ── POST /api/story-session/start ────────────────────────────────────────────

router.post('/start', async (req: AuthRequest, res: Response) => {
  try {
    const parsed = StartSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'Invalid request body', details: parsed.error.flatten() });
    }

    const body = parsed.data;
    const { childProfile } = body;

    const child = await Child.findById(childProfile.childId);
    if (!child) return res.status(404).json({ error: 'Child not found' });

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
        body.minigameFrequency ?? 'every_5th',
      );
    }

    await StoryGraphSession.create({
      _id:        state.sessionId,
      childId:    childProfile.childId,
      mode:       body.mode,
      state,
      lessonName: body.mode === 'educational' ? body.lessonName : undefined,
    });

    return res.json({ sessionId: state.sessionId, mode: state.mode, state });
  } catch (err: any) {
    console.error('❌ Start session error:', err.message);
    res.status(500).json({ error: 'Failed to start story session', details: err.message });
  }
});

// ── POST /api/story-session/:sessionId/tick ───────────────────────────────────

router.post('/:sessionId/tick', async (req: AuthRequest, res: Response) => {
  try {
    const { sessionId } = req.params;

    let session = getSession(sessionId);
    if (!session) {
      const record = await StoryGraphSession.findById(sessionId);
      if (!record) return res.status(404).json({ error: 'Session not found' });
      return res.status(410).json({ error: 'Session expired from memory. Please start a new session.' });
    }

    if (session.session_complete) {
      return res.status(200).json({ sessionComplete: true, state: session });
    }

    const bioParsed    = BiometricSchema.safeParse(req.body.biometrics ?? {});
    const biometrics: BiometricInput = bioParsed.success ? bioParsed.data : {};
    const cameraEnabled = req.body.cameraEnabled !== false;

    console.log(`⏱️  Tick for session ${sessionId} | mode: ${session.mode} | camera: ${cameraEnabled}`);
    const result = await tick(sessionId, biometrics, cameraEnabled);

    await StoryGraphSession.findByIdAndUpdate(sessionId, {
      state:     result.state,
      completed: result.sessionComplete,
      endTime:   result.sessionComplete ? new Date() : undefined,
    });

    return res.json({
      segment:         result.segment,
      imageUrl:        result.imageUrl,
      audioUrl:        req.query.includeAudio === '1' ? result.audioUrl : undefined,
      strategy:        result.strategy,
      score:           result.score,
      trajectory:      result.trajectory,
      arcPosition:     result.arcPosition,
      lessonProgress:  result.lessonProgress,
      minigame:        result.minigame ?? null,
      sessionComplete: result.sessionComplete,
    });
  } catch (err: any) {
    console.error('❌ Tick error:', err.message);
    res.status(500).json({ error: 'Failed to process tick', details: err.message });
  }
});

// ── GET /api/story-session/:sessionId/state ──────────────────────────────────

router.get('/:sessionId/state', async (req: AuthRequest, res: Response) => {
  const { sessionId } = req.params;
  const session = getSession(sessionId);

  if (!session) {
    const record = await StoryGraphSession.findById(sessionId);
    if (!record) return res.status(404).json({ error: 'Session not found' });
    return res.json({ state: record.state });
  }

  return res.json({ state: session });
});

// ── POST /api/story-session/:sessionId/end ───────────────────────────────────

router.post('/:sessionId/end', async (req: AuthRequest, res: Response) => {
  try {
    const { sessionId } = req.params;
    const session = getSession(sessionId);
    if (!session) return res.status(404).json({ error: 'Session not found' });

    let summary: Record<string, unknown>;

    if (session.mode === 'bedtime') {
      summary = {
        mode:                    'bedtime',
        sessionId,
        childName:               session.childProfile.name,
        session_duration_minutes: session.session_minutes,
        sleep_onset_time:        session.sleep_onset_time,
        final_drift_score:       session.drift_score,
        drift_score_curve:       session.drift_score_history,
        total_segments:          session.segments.length,
        arc_position_reached:    session.arc_position,
      };
    } else {
      const ls = session as any;
      summary = {
        mode:                    'educational',
        sessionId,
        childName:               session.childProfile.name,
        lesson_name:             ls.lesson_name,
        lesson_progress:         ls.lesson_progress,
        concepts_introduced:     ls.concepts_introduced,
        concepts_reinforced:     ls.concepts_reinforced,
        engagement_score_curve:  ls.engagement_score_history,
        peak_learning_windows:   ls.engagement_score_history
          .map((s: number, i: number) => ({ minute: i, score: s }))
          .filter((e: any) => e.score >= 60 && e.score <= 85),
        session_duration_minutes: session.session_minutes,
        total_segments:           session.segments.length,
        lesson_complete:          ls.lesson_progress >= 100,
      };
    }

    await StoryGraphSession.findByIdAndUpdate(sessionId, {
      state:     session,
      completed: true,
      endTime:   new Date(),
    });

    deleteSession(sessionId);
    return res.json({ summary });
  } catch (err: any) {
    console.error('❌ End session error:', err.message);
    res.status(500).json({ error: 'Failed to end session', details: err.message });
  }
});

// ── POST /api/story-session/:sessionId/minigame-result ───────────────────────

router.post('/:sessionId/minigame-result', async (req: AuthRequest, res: Response) => {
  try {
    const { sessionId } = req.params;
    const { type, completed, correct, skipped, responseData } = req.body;
    if (!type) return res.status(400).json({ error: 'minigame type required' });
    recordMinigameResult(sessionId, { type, completed, correct, skipped, responseData });
    return res.json({ ok: true });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to record minigame result', details: err.message });
  }
});

// ── GET /api/story-session/history/:childId ──────────────────────────────────

router.get('/history/:childId', async (req: AuthRequest, res: Response) => {
  try {
    const { childId } = req.params;
    const sessions = await StoryGraphSession.find({ childId })
      .sort({ createdAt: -1 })
      .limit(20)
      .select('mode lessonName completed startTime endTime createdAt');
    return res.json({ sessions: sessions.map(s => s.toJSON()) });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to fetch history', details: err.message });
  }
});

export default router;
