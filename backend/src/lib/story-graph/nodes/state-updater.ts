import Anthropic from '@anthropic-ai/sdk';
import { BedtimeState, EducationalState, CharacterState, ArcPosition } from '../types';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

/**
 * Extract or update character states from the new segment using Claude.
 * Lightweight call — small model, focused task.
 */
async function extractCharacterUpdates(
  segment: string,
  existing: Record<string, CharacterState>,
): Promise<Record<string, CharacterState>> {
  try {
    const existingJson = JSON.stringify(existing);
    const response = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 512,
      messages: [
        {
          role: 'user',
          content: `Update the character registry based on this new story segment.

EXISTING CHARACTERS (JSON): ${existingJson}

NEW SEGMENT: "${segment}"

Rules:
- Add any newly named characters.
- Update lastAction and location for characters that appeared.
- Keep description brief (1 sentence).
- Return ONLY valid JSON, no markdown:
{"CharacterName": {"name": "CharacterName", "description": "...", "lastAction": "...", "location": "..."}, ...}`,
        },
      ],
    });

    const text = (response.content[0] as { type: string; text: string }).text;
    const cleaned = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
    const parsed = JSON.parse(cleaned);
    return parsed as Record<string, CharacterState>;
  } catch {
    return existing;
  }
}

// ── Bedtime state updater ──────────────────────────────────────────────────────

export async function updateBedtimeState(
  state: BedtimeState,
  segment: string,
  imageUrl: string,      // permanent R2 URL
  falImageUrl: string,   // Fal.ai CDN URL — temporary, for next image-to-image reference
  audioUrl: string | null,
  drift_score: number,
  drift_trajectory: BedtimeState['drift_trajectory'],
  arc_position: ArcPosition,
  strategy: BedtimeState['current_strategy'],
  guardFailed: boolean,
): Promise<BedtimeState> {
  const characters = await extractCharacterUpdates(segment, state.characters);

  const updated: BedtimeState = {
    ...state,
    story_context: state.story_context + '\n\n' + segment,
    characters,
    arc_position,
    drift_score,
    drift_trajectory,
    drift_score_history: [...state.drift_score_history, drift_score],
    session_minutes: state.session_minutes + 1,
    guard_failures: guardFailed ? state.guard_failures + 1 : 0,
    current_segment: segment,
    current_image_url: imageUrl || state.current_image_url,
    current_audio_url: audioUrl || undefined,
    current_strategy: strategy,
    segments: [
      ...state.segments,
      {
        text: segment,
        imageUrl,
        falImageUrl: falImageUrl || undefined,
        audioUrl: audioUrl || undefined,
        timestamp: Date.now(),
        score: drift_score,
        strategy: strategy ?? 'engagement',
      },
    ],
  };

  // Resolution check
  if (drift_score > 85 && arc_position !== 'resolved') {
    updated.arc_position = 'resolved';
  }

  return updated;
}

// ── Educational state updater ──────────────────────────────────────────────────

export async function updateEducationalState(
  state: EducationalState,
  segment: string,
  imageUrl: string,      // permanent R2 URL
  falImageUrl: string,   // temporary Fal.ai CDN URL
  audioUrl: string | null,
  engagement_score: number,
  engagement_trajectory: EducationalState['engagement_trajectory'],
  lesson_progress: number,
  strategy: EducationalState['current_strategy'],
  conceptIntroduced: string | undefined,
  conceptReinforced: string | undefined,
  guardFailed: boolean,
): Promise<EducationalState> {
  const characters = await extractCharacterUpdates(segment, state.characters);

  const concepts_introduced = conceptIntroduced && !state.concepts_introduced.includes(conceptIntroduced)
    ? [...state.concepts_introduced, conceptIntroduced]
    : state.concepts_introduced;

  const concepts_reinforced = conceptReinforced && !state.concepts_reinforced.includes(conceptReinforced)
    ? [...state.concepts_reinforced, conceptReinforced]
    : state.concepts_reinforced;

  return {
    ...state,
    story_context: state.story_context + '\n\n' + segment,
    characters,
    engagement_score,
    engagement_trajectory,
    engagement_score_history: [...state.engagement_score_history, engagement_score],
    lesson_progress,
    concepts_introduced,
    concepts_reinforced,
    session_minutes: state.session_minutes + 1,
    guard_failures: guardFailed ? state.guard_failures + 1 : 0,
    current_segment: segment,
    current_image_url: imageUrl || state.current_image_url,
    current_audio_url: audioUrl || undefined,
    current_strategy: strategy,
    segments: [
      ...state.segments,
      {
        text: segment,
        imageUrl,
        falImageUrl: falImageUrl || undefined,
        audioUrl: audioUrl || undefined,
        timestamp: Date.now(),
        score: engagement_score,
        strategy: strategy ?? 're_engagement',
      },
    ],
  };
}
