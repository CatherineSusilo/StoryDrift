import { NormalizedBiometrics, DriftTrajectory } from '../types';

// Weights per spec: HRV 40% + Breathing 35% + Movement 25%
const WEIGHTS = {
  calm: 0.40,       // pulse → calm_indicator
  breathing: 0.35,  // breathing → settling_indicator
  movement: 0.25,   // movement → inverted restlessness
};

/**
 * Node 2 (Bedtime) — DRIFT SCORE CALCULATOR
 *
 * drift_score 0-100:
 *   0  = wide awake / wound up
 *   100 = asleep / fully settled
 *
 * Higher score = child is drifting toward sleep.
 */
export function calculateDriftScore(
  biometrics: NormalizedBiometrics,
  previousScore: number,
  history: number[],
): { drift_score: number; drift_trajectory: DriftTrajectory } {
  const stillness = 1 - biometrics.restlessness_indicator;

  const raw =
    biometrics.calm_indicator * WEIGHTS.calm +
    biometrics.settling_indicator * WEIGHTS.breathing +
    stillness * WEIGHTS.movement;

  // Scale 0-1 → 0-100
  const raw_score = Math.round(Math.min(100, Math.max(0, raw * 100)));

  // Smooth with previous score (70% new, 30% history) to avoid jitter
  const quality_weight = biometrics.signal_quality;
  const smoothed = Math.round(
    raw_score * quality_weight + previousScore * (1 - quality_weight),
  );

  const drift_score = Math.min(100, Math.max(0, smoothed));

  // Trajectory: compare to average of last 2 readings
  let drift_trajectory: DriftTrajectory = 'flat';
  if (history.length >= 2) {
    const recentAvg = history.slice(-2).reduce((a, b) => a + b, 0) / 2;
    const delta = drift_score - recentAvg;
    if (delta > 5) drift_trajectory = 'rising';
    else if (delta < -5) drift_trajectory = 'falling';
  }

  return { drift_score, drift_trajectory };
}
