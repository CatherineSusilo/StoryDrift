import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';
import { LessonProgress } from '../models/LessonProgress';
import {
  CURRICULUM,
  getCurriculumForAge,
  findLesson,
  findSection,
  CurriculumLesson,
} from '../lib/curriculum';

const router = Router();

// ── GET /api/curriculum/:age — full curriculum for an age group ───────────

router.get('/:age', async (_req: AuthRequest, res) => {
  const age = parseInt(_req.params.age, 10);
  const curriculum = getCurriculumForAge(age);
  if (!curriculum) return res.status(404).json({ error: `No curriculum for age ${age}` });

  return res.json({
    ageRange: curriculum.ageRange,
    sections: curriculum.sections.map(s => ({
      id:          s.id,
      name:        s.name,
      description: s.description,
      emoji:       s.emoji,
      color:       s.color,
      lessonCount: s.lessons.length,
    })),
  });
});

// ── GET /api/curriculum/section/:sectionId — section roadmap with lessons ──

router.get('/section/:sectionId', async (_req: AuthRequest, res) => {
  const found = findSection(_req.params.sectionId);
  if (!found) return res.status(404).json({ error: 'Section not found' });

  return res.json({
    id:          found.section.id,
    name:        found.section.name,
    description: found.section.description,
    emoji:       found.section.emoji,
    color:       found.section.color,
    lessons:     found.section.lessons.map(l => ({
      id:               l.id,
      order:            l.order,
      name:             l.name,
      description:      l.description,
      concepts:         l.concepts,
      expectedSegments: l.expectedSegments,
      minigameCount:    l.minigameSlots.length,
      unlockAfter:      l.unlockAfter ?? null,
    })),
  });
});

// ── GET /api/curriculum/lesson/:lessonId — full lesson detail ─────────────

router.get('/lesson/:lessonId', async (_req: AuthRequest, res) => {
  const found = findLesson(_req.params.lessonId);
  if (!found) return res.status(404).json({ error: 'Lesson not found' });

  const l = found.lesson;
  return res.json({
    id:               l.id,
    order:            l.order,
    name:             l.name,
    description:      l.description,
    concepts:         l.concepts,
    storyTheme:       l.storyTheme,
    expectedSegments: l.expectedSegments,
    minigameSlots:    l.minigameSlots,
    unlockAfter:      l.unlockAfter ?? null,
    sectionId:        found.section.id,
    sectionName:      found.section.name,
  });
});

// ── GET /api/curriculum/progress/:childId — all progress for a child ─────

router.get('/progress/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const child = await Child.findOne({ _id: req.params.childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    const progress = await LessonProgress.find({ childId: child._id });

    // Build a lookup: lessonId → progress
    const progressMap: Record<string, any> = {};
    for (const p of progress) {
      progressMap[p.lessonId] = p.toJSON();
    }

    // Get curriculum for this child's age
    const curriculum = getCurriculumForAge(child.age);
    if (!curriculum) return res.json({ sections: [], progress: progressMap });

    // Compute per-section summary + unlock status for each lesson
    const sections = curriculum.sections.map(sec => {
      const completedCount = sec.lessons.filter(l => progressMap[l.id]?.completed).length;
      const lessons = sec.lessons.map(l => {
        const lp = progressMap[l.id];
        const unlocked = !l.unlockAfter || !!progressMap[l.unlockAfter]?.completed;
        return {
          id:          l.id,
          order:       l.order,
          name:        l.name,
          unlocked,
          completed:   lp?.completed ?? false,
          stars:       lp?.stars ?? 0,
          attempts:    lp?.attempts ?? 0,
          bestScore:   lp?.bestScore ?? 0,
        };
      });
      return {
        id:             sec.id,
        name:           sec.name,
        emoji:          sec.emoji,
        color:          sec.color,
        totalLessons:   sec.lessons.length,
        completedCount,
        progressPct:    Math.round((completedCount / sec.lessons.length) * 100),
        lessons,
      };
    });

    return res.json({ childId: child._id.toString(), age: child.age, sections });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to get progress', details: err.message });
  }
});

// ── POST /api/curriculum/progress/:childId/:lessonId/complete — mark lesson done ─

router.post('/progress/:childId/:lessonId/complete', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const child = await Child.findOne({ _id: req.params.childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    const found = findLesson(req.params.lessonId);
    if (!found) return res.status(404).json({ error: 'Lesson not found in curriculum' });

    const { stars, sessionId, score } = req.body;
    const earnedStars = Math.min(3, Math.max(0, stars ?? 0));
    const finalScore = score ?? 100;

    const progress = await LessonProgress.findOneAndUpdate(
      { childId: child._id, lessonId: found.lesson.id },
      {
        $set: {
          sectionId:     found.section.id,
          completed:     true,
          completedAt:   new Date(),
          lastSessionId: sessionId,
          ...(earnedStars > 0 ? {} : {}),  // stars are set via $max
        },
        $max: {
          stars:     earnedStars,
          bestScore: finalScore,
        },
        $inc: { attempts: 1 },
        $setOnInsert: {
          childId:   child._id,
          lessonId:  found.lesson.id,
          sectionId: found.section.id,
        },
      },
      { upsert: true, new: true },
    );

    return res.json(progress!.toJSON());
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to update progress', details: err.message });
  }
});

// ── POST /api/curriculum/progress/:childId/:lessonId/start — record attempt ──

router.post('/progress/:childId/:lessonId/start', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const user = await User.findOne({ auth0Id });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const child = await Child.findOne({ _id: req.params.childId, userId: user._id });
    if (!child) return res.status(404).json({ error: 'Child not found' });

    const found = findLesson(req.params.lessonId);
    if (!found) return res.status(404).json({ error: 'Lesson not found in curriculum' });

    // Check unlock prerequisite
    if (found.lesson.unlockAfter) {
      const prereq = await LessonProgress.findOne({
        childId: child._id,
        lessonId: found.lesson.unlockAfter,
        completed: true,
      });
      if (!prereq) {
        return res.status(403).json({ error: 'Prerequisite lesson not completed', required: found.lesson.unlockAfter });
      }
    }

    const progress = await LessonProgress.findOneAndUpdate(
      { childId: child._id, lessonId: found.lesson.id },
      {
        $inc: { attempts: 1 },
        $set: {
          sectionId:     found.section.id,
          lastSessionId: req.body.sessionId,
        },
        $setOnInsert: {
          childId:   child._id,
          lessonId:  found.lesson.id,
          sectionId: found.section.id,
          completed: false,
          stars:     0,
          bestScore: 0,
        },
      },
      { upsert: true, new: true },
    );

    return res.json({
      progress: progress!.toJSON(),
      lesson: {
        id:               found.lesson.id,
        name:             found.lesson.name,
        description:      found.lesson.description,
        concepts:         found.lesson.concepts,
        storyTheme:       found.lesson.storyTheme,
        expectedSegments: found.lesson.expectedSegments,
        minigameSlots:    found.lesson.minigameSlots,
      },
    });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to start lesson', details: err.message });
  }
});

export default router;
