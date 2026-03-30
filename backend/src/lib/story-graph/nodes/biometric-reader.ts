import { BiometricInput, NormalizedBiometrics } from '../types';

// Typical resting ranges for sleeping children
const PULSE_CALM_MIN = 60;
const PULSE_CALM_MAX = 90;
const BREATHING_CALM_MIN = 12;
const BREATHING_CALM_MAX = 18;

/**
 * Camera-off fallback — synthesises plausible signals from session time + mood.
 *
 * Bedtime: drift score rises naturally as minutes pass (faster if "almost_there",
 *          slower if "wound_up").
 * Educational: engagement oscillates around the optimal window so the lesson
 *              progresses steadily without over-stimulating.
 */
export function syntheticBiometrics(
  sessionMinutes: number,
  mode: 'bedtime' | 'educational',
  tonightsMood?: string,
): BiometricInput {
  if (mode === 'bedtime') {
    const moodDelay = tonightsMood === 'wound_up' ? 6 : tonightsMood === 'almost_there' ? -4 : 0;
    const t = Math.max(0, sessionMinutes - moodDelay);

    // Pulse 86 → 63 BPM over 25 minutes  (with small noise)
    const pulse_rate = Math.max(62, 86 - t * 1.0 + (Math.random() - 0.5) * 3);
    // Breathing 17 → 11 breaths/min
    const breathing_rate = Math.max(11, 17 - t * 0.25 + (Math.random() - 0.5) * 0.8);
    // Movement dies down quickly
    const movement_level = Math.max(0, 0.45 - t * 0.02 + Math.random() * 0.04);

    return { pulse_rate, breathing_rate, movement_level, expression_tone: 0.65, signal_quality: 0.55 };
  }

  // Educational: gentle sine wave keeping engagement mostly in the 60-75 optimal window
  const wave = Math.sin(sessionMinutes * 0.5) * 0.1;
  const eye_focus    = Math.min(0.9, Math.max(0.45, 0.70 + wave));
  const expression_tone = Math.min(0.9, Math.max(0.4, 0.65 + wave * 0.5));
  const movement_level  = Math.max(0.1, 0.28 + Math.random() * 0.08);

  return { eye_focus, expression_tone, movement_level, breathing_rate: 15, signal_quality: 0.5 };
}

/**
 * Node 1 — BIOMETRIC READER
 * Normalizes raw camera readings into calm/settling/restlessness indicators.
 */
export function readBiometrics(input: BiometricInput): NormalizedBiometrics {
  const quality = input.signal_quality ?? 0.8;

  // Pulse: calm = low-normal HR (60-90). Map so that values outside range reduce calm.
  let calm_indicator = 0.5;
  if (input.pulse_rate != null) {
    if (input.pulse_rate >= PULSE_CALM_MIN && input.pulse_rate <= PULSE_CALM_MAX) {
      calm_indicator = 1.0;
    } else if (input.pulse_rate < PULSE_CALM_MIN) {
      calm_indicator = 0.7; // very low HR, very calm/drowsy
    } else {
      // Higher HR → less calm
      const excess = (input.pulse_rate - PULSE_CALM_MAX) / 40;
      calm_indicator = Math.max(0, 1.0 - excess);
    }
  }

  // Breathing: settling = slow steady breathing
  let settling_indicator = 0.5;
  if (input.breathing_rate != null) {
    if (input.breathing_rate >= BREATHING_CALM_MIN && input.breathing_rate <= BREATHING_CALM_MAX) {
      settling_indicator = 0.8;
    } else if (input.breathing_rate < BREATHING_CALM_MIN) {
      settling_indicator = 1.0; // very slow breathing → deeply settling
    } else {
      const excess = (input.breathing_rate - BREATHING_CALM_MAX) / 10;
      settling_indicator = Math.max(0, 0.8 - excess);
    }
  }

  // Movement: restlessness = high movement
  const restlessness_indicator = input.movement_level ?? 0.2;

  // Expression / face: emotional calm
  const emotional_state = input.expression_tone ?? 0.6;

  // Eye focus (educational)
  const focus_indicator = input.eye_focus ?? 0.7;

  return {
    calm_indicator,
    settling_indicator,
    restlessness_indicator,
    emotional_state,
    focus_indicator,
    signal_quality: quality,
  };
}
