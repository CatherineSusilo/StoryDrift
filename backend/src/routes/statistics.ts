import { Router } from 'express';
import { AuthRequest } from '../middleware/auth';
import { User } from '../models/User';
import { Child } from '../models/Child';
import { StorySession } from '../models/StorySession';
import { SleepSession } from '../models/SleepSession';

const router = Router();

async function verifyChildOwnership(auth0Id: string, childId: string) {
  const user = await User.findOne({ auth0Id });
  if (!user) return null;
  return Child.findOne({ _id: childId, userId: user._id });
}

router.get('/sleep/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    const { days = '30' } = req.query;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const child = await verifyChildOwnership(auth0Id, childId);
    if (!child) return res.status(404).json({ error: 'Child not found' });

    const daysAgo = new Date();
    daysAgo.setDate(daysAgo.getDate() - parseInt(days as string));

    const sleepSessions = await SleepSession.find({ childId, bedtime: { $gte: daysAgo } }).sort({ bedtime: -1 });

    const totalSessions      = sleepSessions.length;
    const completedSessions  = sleepSessions.filter(s => s.wakeupTime).length;
    const durSessions        = sleepSessions.filter(s => s.duration);
    const avgDuration        = durSessions.length ? durSessions.reduce((sum, s) => sum + s.duration!, 0) / durSessions.length : 0;
    const ttsSessions        = sleepSessions.filter(s => s.timeToSleep);
    const avgTimeToSleep     = ttsSessions.length ? ttsSessions.reduce((sum, s) => sum + s.timeToSleep!, 0) / ttsSessions.length : 0;
    const avgNightWakings    = totalSessions ? sleepSessions.reduce((sum, s) => sum + s.nightWakings, 0) / totalSessions : 0;
    const effSessions        = sleepSessions.filter(s => s.sleepEfficiency);
    const avgSleepEfficiency = effSessions.length ? effSessions.reduce((sum, s) => sum + s.sleepEfficiency!, 0) / effSessions.length : 0;

    const qualityDistribution = {
      poor:      sleepSessions.filter(s => s.quality === 'poor').length,
      fair:      sleepSessions.filter(s => s.quality === 'fair').length,
      good:      sleepSessions.filter(s => s.quality === 'good').length,
      excellent: sleepSessions.filter(s => s.quality === 'excellent').length,
    };

    const dailySleep = new Map<string, { duration: number; count: number }>();
    sleepSessions.forEach(s => {
      if (s.duration) {
        const date = s.bedtime.toISOString().split('T')[0];
        const ex   = dailySleep.get(date) || { duration: 0, count: 0 };
        dailySleep.set(date, { duration: ex.duration + s.duration, count: ex.count + 1 });
      }
    });
    const sleepTrend = Array.from(dailySleep.entries()).map(([date, d]) => ({
      date,
      avgDuration: Math.round(d.duration / d.count),
    }));

    return res.json({
      childId,
      period: { days: parseInt(days as string), from: daysAgo.toISOString(), to: new Date().toISOString() },
      summary: {
        totalSessions,
        completedSessions,
        avgDuration:        Math.round(avgDuration),
        avgTimeToSleep:     Math.round(avgTimeToSleep),
        avgNightWakings:    Math.round(avgNightWakings * 10) / 10,
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

router.get('/stories/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    const { days = '30' } = req.query;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const child = await verifyChildOwnership(auth0Id, childId);
    if (!child) return res.status(404).json({ error: 'Child not found' });

    const daysAgo = new Date();
    daysAgo.setDate(daysAgo.getDate() - parseInt(days as string));

    const storySessions = await StorySession.find({ childId, startTime: { $gte: daysAgo } }).sort({ startTime: -1 });

    const totalSessions      = storySessions.length;
    const completedSessions  = storySessions.filter(s => s.completed).length;
    const durSessions        = storySessions.filter(s => s.duration);
    const avgDuration        = completedSessions && durSessions.length
      ? durSessions.reduce((sum, s) => sum + s.duration!, 0) / completedSessions : 0;
    const avgInitialDriftScore = totalSessions ? storySessions.reduce((sum, s) => sum + s.initialDriftScore, 0) / totalSessions : 0;
    const avgFinalDriftScore   = completedSessions
      ? storySessions.filter(s => s.completed).reduce((sum, s) => sum + s.finalDriftScore, 0) / completedSessions : 0;

    const toneDistribution: Record<string, number> = {};
    const stateDistribution: Record<string, number> = {};
    storySessions.forEach(s => {
      toneDistribution[s.storytellingTone]  = (toneDistribution[s.storytellingTone]  || 0) + 1;
      stateDistribution[s.initialState]     = (stateDistribution[s.initialState]     || 0) + 1;
    });

    const dailyStories = new Map<string, { duration: number; count: number; driftImprovement: number }>();
    storySessions.forEach(s => {
      if (s.duration && s.completed) {
        const date = s.startTime.toISOString().split('T')[0];
        const ex   = dailyStories.get(date) || { duration: 0, count: 0, driftImprovement: 0 };
        dailyStories.set(date, {
          duration:        ex.duration + s.duration,
          count:           ex.count + 1,
          driftImprovement: ex.driftImprovement + (s.finalDriftScore - s.initialDriftScore),
        });
      }
    });
    const storyTrend = Array.from(dailyStories.entries()).map(([date, d]) => ({
      date,
      count:             d.count,
      avgDuration:       Math.round(d.duration / d.count),
      avgDriftImprovement: Math.round((d.driftImprovement / d.count) * 10) / 10,
    }));

    return res.json({
      childId,
      period: { days: parseInt(days as string), from: daysAgo.toISOString(), to: new Date().toISOString() },
      summary: {
        totalSessions,
        completedSessions,
        avgDuration:           Math.round(avgDuration),
        avgInitialDriftScore:  Math.round(avgInitialDriftScore),
        avgFinalDriftScore:    Math.round(avgFinalDriftScore),
        avgDriftImprovement:   Math.round((avgFinalDriftScore - avgInitialDriftScore) * 10) / 10,
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

router.get('/insights/:childId', async (req: AuthRequest, res) => {
  try {
    const auth0Id = req.auth?.payload?.sub;
    const { childId } = req.params;
    if (!auth0Id) return res.status(401).json({ error: 'Unauthorized' });

    const child = await verifyChildOwnership(auth0Id, childId);
    if (!child) return res.status(404).json({ error: 'Child not found' });

    const [recentStories, recentSleep] = await Promise.all([
      StorySession.find({ childId }).sort({ startTime: -1 }).limit(10),
      SleepSession.find({ childId }).sort({ bedtime: -1 }).limit(10),
    ]);

    const insights: any[] = [];

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

    const recentQuality = recentSleep.filter(s => s.quality).slice(0, 5);
    if (recentQuality.length >= 3) {
      const goodNights = recentQuality.filter(s => s.quality === 'good' || s.quality === 'excellent').length;
      const pct = (goodNights / recentQuality.length) * 100;
      if (pct >= 80) {
        insights.push({ type: 'positive', title: 'Excellent sleep quality', description: `${child.name} has had ${goodNights} out of ${recentQuality.length} nights with good or excellent sleep.` });
      } else if (pct < 40) {
        insights.push({ type: 'warning', title: 'Sleep quality could improve', description: 'Consider adjusting bedtime routine or story preferences to improve sleep quality.' });
      }
    }

    if (recentStories.length >= 5) {
      const toneEff: Record<string, number[]> = {};
      recentStories.forEach(s => {
        if (s.completed) {
          (toneEff[s.storytellingTone] ||= []).push(s.finalDriftScore - s.initialDriftScore);
        }
      });
      let bestTone = '', bestAvg = 0;
      Object.entries(toneEff).forEach(([tone, scores]) => {
        const avg = scores.reduce((a, b) => a + b, 0) / scores.length;
        if (avg > bestAvg) { bestAvg = avg; bestTone = tone; }
      });
      if (bestTone) {
        insights.push({ type: 'suggestion', title: 'Most effective storytelling tone', description: `${bestTone.charAt(0).toUpperCase() + bestTone.slice(1)} stories work best for ${child.name}.` });
      }
    }

    if (recentStories.length < 3 && recentSleep.length < 3) {
      insights.push({ type: 'info', title: 'Build a routine', description: `Track more bedtime sessions to unlock personalized insights for ${child.name}.` });
    }

    const weekAgo = new Date();
    weekAgo.setDate(weekAgo.getDate() - 7);
    return res.json({
      childId,
      childName: child.name,
      insights,
      recentActivity: {
        storiesThisWeek: recentStories.filter(s => s.startTime >= weekAgo).length,
        sleepSessionsThisWeek: recentSleep.filter(s => s.bedtime >= weekAgo).length,
      },
    });
  } catch (error) {
    console.error('Get insights error:', error instanceof Error ? error.message : String(error));
    res.status(500).json({ error: 'Failed to get insights' });
  }
});

export default router;
