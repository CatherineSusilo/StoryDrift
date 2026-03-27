import { NormalizedBiometrics, DriftTrajectory } from '../types';

// Weights per spec: Eye focus 35% + Facial expression 30% + Movement 20% + Breathing 15%
const WEIGHTS = {
  eye_focus: 0.35,
  expression: 0.30,
  movement: 0.20,
  breathing: 0.15,
};

/**
 * Node 2 (Educational) — ENGAGEMENT SCORE CALCULATOR
 *
 * engagement_score 0-100:
 *   0-30  = disengaged (bored / distracted)
 *   30-60 = baseline (passively following)
 *   60-85 = optimal (active attention, learning window ★)
 *   85-100 = overstimulated (too much too fast)
 */
export function calculateEngagementScore(
  biometrics: NormalizedBiometrics,
  previousScore: number,
  history: number[],
): { engagement_score: number; engagement_trajectory: DriftTrajectory } {
  const stillness = 1 - biometrics.restlessness_indicator;

  const raw =
    biometrics.focus_indicator * WEIGHTS.eye_focus +
    biometrics.emotional_state * WEIGHTS.expression +
    stillness * WEIGHTS.movement +
    biometrics.settling_indicator * WEIGHTS.breathing;

  const raw_score = Math.round(Math.min(100, Math.max(0, raw * 100)));

  const quality_weight = biometrics.signal_quality;
  const smoothed = Math.round(
    raw_score * quality_weight + previousScore * (1 - quality_weight),
  );

  const engagement_score = Math.min(100, Math.max(0, smoothed));

  let engagement_trajectory: DriftTrajectory = 'flat';
  if (history.length >= 2) {
    const recentAvg = history.slice(-2).reduce((a, b) => a + b, 0) / 2;
    const delta = engagement_score - recentAvg;
    if (delta > 5) engagement_trajectory = 'rising';
    else if (delta < -5) engagement_trajectory = 'falling';
  }

  return { engagement_score, engagement_trajectory };
}
