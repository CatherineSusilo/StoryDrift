import { v4 as uuid } from 'uuid';
import {
  GraphState,
  BedtimeState,
  EducationalState,
  BiometricInput,
  ChildProfile,
  TickResult,
  MinigameTrigger,
  MinigameResult,
} from './types';
import { readBiometrics, syntheticBiometrics } from './nodes/biometric-reader';
import { calculateDriftScore } from './nodes/drift-calculator';
import { calculateEngagementScore } from './nodes/engagement-calculator';
import { routeNarrativeStrategy } from './nodes/narrative-router';
import { routeEducationalStrategy } from './nodes/educational-router';
import { planLesson } from './nodes/lesson-planner';
import {
  generateBedtimeSegment,
  generateEducationalSegment,
  generateResolutionSegment,
  generateLessonCompletionSegment,
} from './nodes/story-generator';
import { runHallucinationGuard } from './nodes/hallucination-guard';
import { generateSceneImage } from './nodes/image-generator';
import { generateVoice } from './nodes/voice-output';
import { updateBedtimeState, updateEducationalState } from './nodes/state-updater';
import { decidMinigame } from './nodes/minigame-trigger';

// In-memory session store (persisted to DB via routes)
const sessions = new Map<string, GraphState>();

// Returns the segment gap for a given frequency — used to initialise the
// counter so the first minigame fires on tick 2 (one story segment shown first).
function minGapForFrequency(freq: string): number {
  switch (freq) {
    case 'every_paragraph': return 1;
    case 'every_3rd':       return 3;
    case 'every_5th':       return 5;
    default:                return 5;
  }
}

// ── Session initialisation ─────────────────────────────────────────────────────

export function createBedtimeSession(childProfile: ChildProfile, knownCharacters: KnownCharacter[] = []): BedtimeState {
  const sessionId = uuid();
  const state: BedtimeState = {
    mode: 'bedtime',
    sessionId,
    childId: childProfile.childId,
    childProfile,
    drift_score: 0,
    drift_trajectory: 'flat',
    drift_score_history: [],
    story_context: '',
    characters: {},
    arc_position: 'opening',
    session_minutes: 0,
    guard_failures: 0,
    knownCharacters,
    segments: [],
    session_complete: false,
  };
  sessions.set(sessionId, state);
  return state;
}

export async function createEducationalSession(
  childProfile: ChildProfile,
  lessonName: string,
  lessonDescription: string,
  minigameFrequency: 'none' | 'every_5th' | 'every_3rd' | 'every_paragraph' = 'every_5th',
  knownCharacters: KnownCharacter[] = [],
  curriculumLessonId?: string,
): Promise<EducationalState> {
  const sessionId = uuid();

  // Lesson Planner runs once at session start
  console.log('📚 Running lesson planner...');
  const lesson_plan = await planLesson(lessonName, lessonDescription, childProfile);
  console.log('✅ Lesson plan created:', lesson_plan.concept_sequence);

  const state: EducationalState = {
    mode: 'educational',
    sessionId,
    childId: childProfile.childId,
    childProfile,
    engagement_score: 50,
    engagement_trajectory: 'flat',
    engagement_score_history: [],
    curriculumLessonId,
    lesson_name: lessonName,
    lesson_description: lessonDescription,
    lesson_plan,
    lesson_progress: 0,
    concepts_introduced: [],
    concepts_reinforced: [],
    story_context: '',
    characters: {},
    session_minutes: 0,
    guard_failures: 0,
    knownCharacters,
    segments: [],
    minigame_events: [],
    segments_since_last_minigame: minGapForFrequency(minigameFrequency),   // fires on tick 2
    minigame_frequency: minigameFrequency,
    session_complete: false,
  };
  sessions.set(sessionId, state);
  return state;
}

export function getSession(sessionId: string): GraphState | undefined {
  return sessions.get(sessionId);
}

export function deleteSession(sessionId: string): void {
  sessions.delete(sessionId);
}

// ── Main tick: runs the full node pipeline ─────────────────────────────────────

export async function tick(
  sessionId: string,
  biometrics: BiometricInput,
  cameraEnabled: boolean = true,
): Promise<TickResult> {
  const state = sessions.get(sessionId);
  if (!state) throw new Error(`Session ${sessionId} not found`);

  // Camera-off fallback: synthesise signals from time + profile
  const effectiveBiometrics: BiometricInput = cameraEnabled
    ? biometrics
    : syntheticBiometrics(
        state.session_minutes,
        state.mode,
        state.mode === 'bedtime' ? state.childProfile.tonightsMood : undefined,
      );

  if (state.mode === 'bedtime') {
    return tickBedtime(state as BedtimeState, effectiveBiometrics);
  } else {
    return tickEducational(state as EducationalState, effectiveBiometrics);
  }
}

// ── BEDTIME TICK ───────────────────────────────────────────────────────────────

async function tickBedtime(state: BedtimeState, biometrics: BiometricInput): Promise<TickResult> {
  // Node 1 — Biometric Reader
  const normalised = readBiometrics(biometrics);

  // Node 2 — Drift Score Calculator
  const { drift_score, drift_trajectory } = calculateDriftScore(
    normalised,
    state.drift_score,
    state.drift_score_history,
  );
  console.log(`🌙 Drift: ${drift_score} (${drift_trajectory})`);

  // Resolution protocol
  if (drift_score > 85 && state.arc_position !== 'resolved') {
    console.log('😴 Resolution protocol triggered');
    const segment = await generateResolutionSegment(state);
    const { imageUrl, falUrl } = await generateSceneImage(segment, drift_score, 'bedtime',
      getLastFalUrls(state));
    const voice = await generateVoice(segment, drift_score, 'bedtime', state.childProfile.narratorVoiceId);

    const updated = await updateBedtimeState(
      state, segment, imageUrl, falUrl, voice?.audioBase64 ?? null,
      drift_score, drift_trajectory, 'resolved', 'resolution', false,
    );
    updated.sleep_onset_time = new Date().toISOString();
    updated.session_complete = true;
    sessions.set(state.sessionId, updated);

    return toTickResult(updated, segment, imageUrl, voice?.audioBase64 ?? null, 'resolution');
  }

  // Node 3 — Narrative Strategy Router
  const { strategy, arc_position } = routeNarrativeStrategy({ ...state, drift_score });

  // Node 4 — Story Generator
  let segment = await generateBedtimeSegment(
    { ...state, drift_score, arc_position },
    strategy,
  );

  // Node 5 — Hallucination Guard (with retry)
  let guard = await runHallucinationGuard(segment, { ...state, drift_score }, state.guard_failures);
  let guardFailed = !guard.passed;

  if (!guard.passed) {
    // One retry
    const retry = await generateBedtimeSegment({ ...state, drift_score, arc_position }, strategy);
    const guard2 = await runHallucinationGuard(retry, { ...state, drift_score }, state.guard_failures + 1);
    guardFailed = !guard2.passed;
    guard = guard2;
  }

  segment = guard.segment;

  // Node 6 — Image Generator
  const { imageUrl, falUrl } = await generateSceneImage(
    segment, drift_score, 'bedtime', getLastFalUrls(state),
  );

  // Node 7 — Voice Output
  const voice = await generateVoice(segment, drift_score, 'bedtime', state.childProfile.narratorVoiceId);

  // Node 8 — State Updater
  const updated = await updateBedtimeState(
    state, segment, imageUrl, falUrl, voice?.audioBase64 ?? null,
    drift_score, drift_trajectory, arc_position, strategy.strategy, guardFailed,
  );
  sessions.set(state.sessionId, updated);

  return toTickResult(updated, segment, imageUrl, voice?.audioBase64 ?? null, strategy.strategy);
}

// ── EDUCATIONAL TICK ───────────────────────────────────────────────────────────

async function tickEducational(
  state: EducationalState,
  biometrics: BiometricInput,
): Promise<TickResult> {
  // Node 1 — Biometric Reader
  const normalised = readBiometrics(biometrics);

  // Node 2 — Engagement Score Calculator
  const { engagement_score, engagement_trajectory } = calculateEngagementScore(
    normalised,
    state.engagement_score,
    state.engagement_score_history,
  );
  console.log(`📚 Engagement: ${engagement_score} (${engagement_trajectory})`);

  // Node 3 — Lesson Progress Checker (inline)
  // Handled inside educational router

  // Node 4 — Educational Strategy Router
  const { result: strategy, lesson_progress } = routeEducationalStrategy({
    ...state,
    engagement_score,
  });

  // Lesson completion check
  const allConcepts = state.lesson_plan?.concept_sequence ?? [];
  const allIntroduced = allConcepts.every((c) => state.concepts_introduced.includes(c));
  const allReinforced = allConcepts.every((c) => state.concepts_reinforced.includes(c));
  const lessonComplete = lesson_progress >= 100 || (allIntroduced && allReinforced);

  if (lessonComplete) {
    console.log('🎓 Lesson completion protocol triggered');
    const segment = await generateLessonCompletionSegment({ ...state, engagement_score });
    const { imageUrl, falUrl } = await generateSceneImage(segment, engagement_score, 'educational',
      getLastFalUrls(state), state.lesson_name);
    const voice = await generateVoice(segment, engagement_score, 'educational', state.childProfile.narratorVoiceId);

    const updated = await updateEducationalState(
      state, segment, imageUrl, falUrl, voice?.audioBase64 ?? null,
      engagement_score, engagement_trajectory, 100,
      'consolidation', undefined, undefined, false,
    );
    updated.lesson_progress = 100;
    updated.session_complete = true;
    sessions.set(state.sessionId, updated);

    return toTickResult(updated, segment, imageUrl, voice?.audioBase64 ?? null, 'consolidation');
  }

  // Node 5 — Story Generator
  let segment = await generateEducationalSegment(
    { ...state, engagement_score },
    strategy,
  );

  // Node 6 — Hallucination Guard
  let guard = await runHallucinationGuard(
    segment, { ...state, engagement_score }, state.guard_failures,
  );
  let guardFailed = !guard.passed;

  if (!guard.passed) {
    const retry = await generateEducationalSegment({ ...state, engagement_score }, strategy);
    const guard2 = await runHallucinationGuard(
      retry, { ...state, engagement_score }, state.guard_failures + 1,
    );
    guardFailed = !guard2.passed;
    guard = guard2;
  }

  segment = guard.segment;

  // Node 7 — Image Generator (highlight concept visually)
  const { imageUrl, falUrl } = await generateSceneImage(
    segment, engagement_score, 'educational',
    getLastFalUrls(state),
    strategy.next_concept,
  );

  // Node 8 — Voice Output
  const voice = await generateVoice(segment, engagement_score, 'educational', state.childProfile.narratorVoiceId);

  // Node 9 — State Updater
  const conceptIntroduced = !strategy.hold_concept ? strategy.next_concept : undefined;
  const conceptReinforced =
    strategy.strategy === 'optimal_learning' && strategy.next_concept
      ? strategy.next_concept
      : undefined;

  const updated = await updateEducationalState(
    state, segment, imageUrl, falUrl, voice?.audioBase64 ?? null,
    engagement_score, engagement_trajectory, lesson_progress,
    strategy.strategy, conceptIntroduced, conceptReinforced, guardFailed,
  );

  // Minigame Trigger — decide if a minigame should follow this segment
  let minigame: MinigameTrigger | undefined;
  const updatedWithMeta = {
    ...updated,
    segments_since_last_minigame: (updated as EducationalState).segments_since_last_minigame + 1,
  } as EducationalState;

  const trigger = await decidMinigame(updatedWithMeta, segment);
  if (trigger) {
    minigame = trigger;
    updatedWithMeta.segments_since_last_minigame = 0;
    updatedWithMeta.minigame_events = [
      ...(updatedWithMeta.minigame_events ?? []),
      { type: trigger.type, segmentIndex: updated.segments.length - 1, triggeredAt: Date.now() },
    ];
  }

  sessions.set(state.sessionId, updatedWithMeta);

  return { ...toTickResult(updatedWithMeta, segment, imageUrl, voice?.audioBase64 ?? null, strategy.strategy), minigame };
}

// ── Helpers ────────────────────────────────────────────────────────────────────

// Returns the last 2 *Fal.ai CDN URLs* — these are what we pass as the
// image-to-image reference, because Fal.ai's servers can only reach their
// own CDN, not our local Express /images/ endpoint.
// CDN URLs are valid for ~1h, which is always enough within an active session.
function getLastFalUrls(state: GraphState): string[] {
  return state.segments
    .slice(-2)
    .map((s) => s.falImageUrl)
    .filter((u): u is string => !!u);
}

function toTickResult(
  state: GraphState,
  segment: string,
  imageUrl: string,
  audioUrl: string | null,
  strategy: string,
): TickResult {
  const score = state.mode === 'bedtime' ? state.drift_score : state.engagement_score;
  const trajectory =
    state.mode === 'bedtime' ? state.drift_trajectory : state.engagement_trajectory;

  return {
    segment,
    imageUrl: imageUrl || undefined,
    audioUrl: audioBase64 ? `data:audio/mpeg;base64,${audioBase64}` : undefined,
    strategy,
    score,
    trajectory,
    arcPosition: state.mode === 'bedtime' ? state.arc_position : undefined,
    lessonProgress: state.mode === 'educational' ? state.lesson_progress : undefined,
    sessionComplete: state.session_complete,
    state,
  };
}

// ── Record minigame result ─────────────────────────────────────────────────────

export function recordMinigameResult(sessionId: string, result: MinigameResult): void {
  const state = sessions.get(sessionId);
  if (!state || state.mode !== 'educational') return;

  const edu = state as EducationalState;
  const events = [...(edu.minigame_events ?? [])];
  const lastEvent = events[events.length - 1];
  if (lastEvent && !lastEvent.result) {
    lastEvent.result = result;
  }

  sessions.set(sessionId, { ...edu, minigame_events: events });
}
