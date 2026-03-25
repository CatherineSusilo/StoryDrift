import { BiometricInput, NormalizedBiometrics } from '../types';

// Typical resting ranges for sleeping children
const PULSE_CALM_MIN = 60;
const PULSE_CALM_MAX = 90;
const BREATHING_CALM_MIN = 12;
const BREATHING_CALM_MAX = 18;

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
