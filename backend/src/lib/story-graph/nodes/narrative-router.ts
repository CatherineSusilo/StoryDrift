import { NarrativeStrategy, BedtimeState, ArcPosition } from '../types';

/**
 * Node 3 (Bedtime) — NARRATIVE STRATEGY ROUTER
 *
 * Maps drift_score → strategy and prompt directive.
 * Also advances arc_position when appropriate.
 */
export function routeNarrativeStrategy(state: BedtimeState): {
  strategy: NarrativeStrategy;
  arc_position: ArcPosition;
} {
  const { drift_score, arc_position, session_minutes } = state;

  let strategy: NarrativeStrategy;
  let next_arc = arc_position;

  if (drift_score <= 25) {
    strategy = {
      strategy: 'engagement',
      prompt_directive:
        'Write a vivid, engaging scene. Introduce a small problem or mystery for the character to solve. ' +
        'Use active, sensory language. Keep the child's attention with something unexpected or delightful.',
    };
    if (arc_position === 'opening' && session_minutes >= 3) next_arc = 'rising';
  } else if (drift_score <= 50) {
    strategy = {
      strategy: 'settling',
      prompt_directive:
        'Reduce conflict and tension. Introduce warmth, safety, and comfort. ' +
        'Slow the pacing slightly. Use gentle, reassuring imagery. ' +
        'The character finds something soothing — a warm fire, a soft meadow, a friendly companion.',
    };
    if (arc_position === 'rising') next_arc = 'climax';
  } else if (drift_score <= 75) {
    strategy = {
      strategy: 'winding_down',
      prompt_directive:
        'Move toward resolution. Shorten sentences. Use quieter, softer imagery — moonlight, whispers, gentle breezes. ' +
        'Introduce repetitive, soothing language. The world is growing still and peaceful.',
    };
    if (arc_position === 'climax') next_arc = 'winding_down';
  } else {
    strategy = {
      strategy: 'resolution',
      prompt_directive:
        'The protagonist finds what they were seeking. The world goes completely still. ' +
        'Use very short sentences. Speak in hushed tones. ' +
        'End with the character closing their eyes, breathing slowly, and drifting into peaceful rest. ' +
        'The story breathes out its last sentence.',
    };
    next_arc = 'winding_down';
  }

  return { strategy, arc_position: next_arc };
}
