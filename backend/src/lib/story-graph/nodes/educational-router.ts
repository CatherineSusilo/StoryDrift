import { EducationalStrategyResult, EducationalState } from '../types';

/**
 * Node 4 (Educational) — EDUCATIONAL STRATEGY ROUTER
 *
 * Maps engagement_score → strategy, manages lesson progress,
 * and determines which concept to introduce/reinforce next.
 */
export function routeEducationalStrategy(state: EducationalState): {
  result: EducationalStrategyResult;
  lesson_progress: number;
} {
  const {
    engagement_score,
    lesson_plan,
    concepts_introduced,
    concepts_reinforced,
    lesson_progress,
  } = state;

  // Determine next concept from lesson plan
  const sequence = lesson_plan?.concept_sequence ?? [];
  const nextConcept = sequence.find((c) => !concepts_introduced.includes(c));
  const unreinforcedIntroduced = concepts_introduced.find((c) => !concepts_reinforced.includes(c));

  let result: EducationalStrategyResult;

  if (engagement_score <= 30) {
    result = {
      strategy: 're_engagement',
      prompt_directive:
        'The child is disengaged. Introduce an unexpected event that will grab their attention. ' +
        'Have the character ask the child a direct question (e.g. "Can you help me count these?"). ' +
        'Change the scene or have the character do something surprising. ' +
        'Do NOT introduce a new concept yet — re-engage first.',
      hold_concept: true,
    };
  } else if (engagement_score <= 60) {
    result = {
      strategy: 'concept_introduction',
      prompt_directive:
        'The child is baseline engaged. Weave the next concept naturally into the narrative. ' +
        'Let the character encounter the concept as part of the story — show, do not tell. ' +
        "Do NOT explain the concept — demonstrate it through the character's actions.",
      next_concept: nextConcept,
      hold_concept: false,
    };
  } else if (engagement_score <= 85) {
    // Prime learning window ★
    const isReinforcing = !!unreinforcedIntroduced;
    result = {
      strategy: 'optimal_learning',
      prompt_directive:
        'This is the PRIME LEARNING WINDOW. ' +
        (isReinforcing
          ? `Reinforce the previously introduced concept: "${unreinforcedIntroduced}". ` +
            'Create an interactive moment where the child can participate. ' +
            'Connect to the concept already introduced and deepen understanding.'
          : `Introduce the next concept: "${nextConcept}". ` +
            'Add depth and complexity appropriate for this age. ' +
            'Create an interactive moment — pause and give the child space to respond.'),
      next_concept: isReinforcing ? unreinforcedIntroduced : nextConcept,
      hold_concept: false,
    };
  } else {
    result = {
      strategy: 'consolidation',
      prompt_directive:
        'The child is overstimulated — slow down. ' +
        'Have the character pause and reflect on what was just discovered. ' +
        'Celebrate the learning with warmth and simplicity. ' +
        'Use simpler language and a slower pace. Do NOT introduce a new concept.',
      hold_concept: true,
    };
  }

  // Advance lesson_progress based on strategy and concepts state
  let newProgress = lesson_progress;
  if (!result.hold_concept && sequence.length > 0) {
    const total_steps = sequence.length * 2; // each concept: introduced + reinforced
    const done_steps = concepts_introduced.length + concepts_reinforced.length;
    newProgress = Math.min(100, Math.round((done_steps / total_steps) * 100));
  }

  return { result, lesson_progress: newProgress };
}
