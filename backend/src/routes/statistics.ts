import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';

const router = Router();

// Get sleep statistics for a child
router.get('/sleep/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    const { days = '30' } = req.query; // Default to last 30 days

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

    const daysAgo = new Date();
    daysAgo.setDate(daysAgo.getDate() - parseInt(days as string));

    const sleepSessions = await prisma.sleepSession.findMany({
      where: {
        childId,
        bedtime: {
          gte: daysAgo,
        },
      },
      orderBy: { bedtime: 'desc' },
    });

    // Calculate statistics
    const totalSessions = sleepSessions.length;
    const completedSessions = sleepSessions.filter(s => s.wakeupTime).length;
    
    const avgDuration = completedSessions > 0
      ? sleepSessions
          .filter(s => s.duration)
          .reduce((sum, s) => sum + (s.duration || 0), 0) / completedSessions
      : 0;

    const avgTimeToSleep = sleepSessions
      .filter(s => s.timeToSleep)
      .reduce((sum, s) => sum + (s.timeToSleep || 0), 0) / (sleepSessions.filter(s => s.timeToSleep).length || 1);

    const avgNightWakings = sleepSessions
      .reduce((sum, s) => sum + s.nightWakings, 0) / (totalSessions || 1);

    const avgSleepEfficiency = sleepSessions
      .filter(s => s.sleepEfficiency)
      .reduce((sum, s) => sum + (s.sleepEfficiency || 0), 0) / (sleepSessions.filter(s => s.sleepEfficiency).length || 1);

    // Quality distribution
    const qualityDistribution = {
      poor: sleepSessions.filter(s => s.quality === 'poor').length,
      fair: sleepSessions.filter(s => s.quality === 'fair').length,
      good: sleepSessions.filter(s => s.quality === 'good').length,
      excellent: sleepSessions.filter(s => s.quality === 'excellent').length,
    };

    // Sleep trend (daily average for the period)
    const dailySleep = new Map<string, { duration: number; count: number }>();
    sleepSessions.forEach(session => {
      if (session.duration) {
        const date = session.bedtime.toISOString().split('T')[0];
        const existing = dailySleep.get(date) || { duration: 0, count: 0 };
        dailySleep.set(date, {
          duration: existing.duration + session.duration,
          count: existing.count + 1,
        });
      }
    });

    const sleepTrend = Array.from(dailySleep.entries()).map(([date, data]) => ({
      date,
      avgDuration: Math.round(data.duration / data.count),
    }));

    res.json({
      childId,
      period: {
        days: parseInt(days as string),
        from: daysAgo.toISOString(),
        to: new Date().toISOString(),
      },
      summary: {
        totalSessions,
        completedSessions,
        avgDuration: Math.round(avgDuration),
        avgTimeToSleep: Math.round(avgTimeToSleep),
        avgNightWakings: Math.round(avgNightWakings * 10) / 10,
        avgSleepEfficiency: Math.round(avgSleepEfficiency * 10) / 10,
      },
      qualityDistribution,
      sleepTrend,
    });
  } catch (error) {
    console.error('Get sleep statistics error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get sleep statistics' });
  }
});

// Get story statistics for a child
router.get('/stories/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    const { days = '30' } = req.query;

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

    const daysAgo = new Date();
    daysAgo.setDate(daysAgo.getDate() - parseInt(days as string));

    const storySessions = await prisma.storySession.findMany({
      where: {
        childId,
        startTime: {
          gte: daysAgo,
        },
      },
      orderBy: { startTime: 'desc' },
    });

    // Calculate statistics
    const totalSessions = storySessions.length;
    const completedSessions = storySessions.filter(s => s.completed).length;
    
    const avgDuration = completedSessions > 0
      ? storySessions
          .filter(s => s.duration)
          .reduce((sum, s) => sum + (s.duration || 0), 0) / completedSessions
      : 0;

    const avgInitialDriftScore = storySessions
      .reduce((sum, s) => sum + s.initialDriftScore, 0) / (totalSessions || 1);

    const avgFinalDriftScore = completedSessions > 0
      ? storySessions
          .filter(s => s.completed)
          .reduce((sum, s) => sum + s.finalDriftScore, 0) / completedSessions
      : 0;

    const avgDriftImprovement = avgFinalDriftScore - avgInitialDriftScore;

    // Tone distribution
    const toneDistribution: Record<string, number> = {};
    storySessions.forEach(s => {
      toneDistribution[s.storytellingTone] = (toneDistribution[s.storytellingTone] || 0) + 1;
    });

    // Initial state distribution
    const stateDistribution: Record<string, number> = {};
    storySessions.forEach(s => {
      stateDistribution[s.initialState] = (stateDistribution[s.initialState] || 0) + 1;
    });

    // Story duration trend
    const dailyStories = new Map<string, { duration: number; count: number; driftImprovement: number }>();
    storySessions.forEach(session => {
      if (session.duration && session.completed) {
        const date = session.startTime.toISOString().split('T')[0];
        const existing = dailyStories.get(date) || { duration: 0, count: 0, driftImprovement: 0 };
        dailyStories.set(date, {
          duration: existing.duration + session.duration,
          count: existing.count + 1,
          driftImprovement: existing.driftImprovement + (session.finalDriftScore - session.initialDriftScore),
        });
      }
    });

    const storyTrend = Array.from(dailyStories.entries()).map(([date, data]) => ({
      date,
      avgDuration: Math.round(data.duration / data.count),
      avgDriftImprovement: Math.round((data.driftImprovement / data.count) * 10) / 10,
    }));

    res.json({
      childId,
      period: {
        days: parseInt(days as string),
        from: daysAgo.toISOString(),
        to: new Date().toISOString(),
      },
      summary: {
        totalSessions,
        completedSessions,
        avgDuration: Math.round(avgDuration),
        avgInitialDriftScore: Math.round(avgInitialDriftScore),
        avgFinalDriftScore: Math.round(avgFinalDriftScore),
        avgDriftImprovement: Math.round(avgDriftImprovement * 10) / 10,
      },
      toneDistribution,
      stateDistribution,
      storyTrend,
    });
  } catch (error) {
    console.error('Get story statistics error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get story statistics' });
  }
});

// Get combined insights for a child
router.get('/insights/:childId', async (req: AuthRequest, res) => {
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

    // Get recent story and sleep sessions
    const recentStories = await prisma.storySession.findMany({
      where: { childId },
      orderBy: { startTime: 'desc' },
      take: 10,
    });

    const recentSleep = await prisma.sleepSession.findMany({
      where: { childId },
      orderBy: { bedtime: 'desc' },
      take: 10,
    });

    // Calculate insights
    const insights = [];

    // Insight 1: Story effectiveness
    const completedStories = recentStories.filter(s => s.completed);
    if (completedStories.length >= 3) {
      const avgImprovement = completedStories
        .reduce((sum, s) => sum + (s.finalDriftScore - s.initialDriftScore), 0) / completedStories.length;
      
      if (avgImprovement > 60) {
        insights.push({
          type: 'positive',
          title: 'Stories are highly effective',
          description: `Stories are helping ${child.name} fall asleep quickly, with an average drift improvement of ${Math.round(avgImprovement)} points.`,
        });
      }
    }

    // Insight 2: Sleep quality trend
    const recentQuality = recentSleep.filter(s => s.quality).slice(0, 5);
    if (recentQuality.length >= 3) {
      const goodNights = recentQuality.filter(s => s.quality === 'good' || s.quality === 'excellent').length;
      const percentage = (goodNights / recentQuality.length) * 100;
      
      if (percentage >= 80) {
        insights.push({
          type: 'positive',
          title: 'Excellent sleep quality',
          description: `${child.name} has had ${goodNights} out of ${recentQuality.length} nights with good or excellent sleep.`,
        });
      } else if (percentage < 40) {
        insights.push({
          type: 'warning',
          title: 'Sleep quality could improve',
          description: `Consider adjusting bedtime routine or story preferences to improve sleep quality.`,
        });
      }
    }

    // Insight 3: Best storytelling tone
    if (recentStories.length >= 5) {
      const toneEffectiveness: Record<string, number[]> = {};
      recentStories.forEach(s => {
        if (s.completed) {
          if (!toneEffectiveness[s.storytellingTone]) {
            toneEffectiveness[s.storytellingTone] = [];
          }
          toneEffectiveness[s.storytellingTone].push(s.finalDriftScore - s.initialDriftScore);
        }
      });

      let bestTone = '';
      let bestAvg = 0;
      Object.entries(toneEffectiveness).forEach(([tone, scores]) => {
        const avg = scores.reduce((a, b) => a + b, 0) / scores.length;
        if (avg > bestAvg) {
          bestAvg = avg;
          bestTone = tone;
        }
      });

      if (bestTone) {
        insights.push({
          type: 'suggestion',
          title: 'Most effective storytelling tone',
          description: `${bestTone.charAt(0).toUpperCase() + bestTone.slice(1)} stories work best for ${child.name}.`,
        });
      }
    }

    // Insight 4: Consistency recommendation
    if (recentStories.length < 3 && recentSleep.length < 3) {
      insights.push({
        type: 'info',
        title: 'Build a routine',
        description: `Track more bedtime sessions to unlock personalized insights for ${child.name}.`,
      });
    }

    res.json({
      childId,
      childName: child.name,
      insights,
      recentActivity: {
        storiesThisWeek: recentStories.filter(s => {
          const weekAgo = new Date();
          weekAgo.setDate(weekAgo.getDate() - 7);
          return s.startTime >= weekAgo;
        }).length,
        sleepSessionsThisWeek: recentSleep.filter(s => {
          const weekAgo = new Date();
          weekAgo.setDate(weekAgo.getDate() - 7);
          return s.bedtime >= weekAgo;
        }).length,
      },
    });
  } catch (error) {
    console.error('Get insights error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get insights' });
  }
});

export default router;
