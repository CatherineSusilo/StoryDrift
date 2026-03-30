import Anthropic from '@anthropic-ai/sdk';
import { GraphState } from '../types';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

interface GuardResult {
  passed: boolean;
  segment: string;
  issues?: string[];
}

// Fallback templates when guard fails twice
const BEDTIME_FALLBACK = (score: number): string => {
  if (score > 75)
    return 'The world grew very quiet. The stars blinked softly overhead, one by one. Everything was still and peaceful and safe.';
  if (score > 50)
    return 'The little creature settled into the soft grass. A gentle breeze whispered through the leaves. Slowly, everything slowed down.';
  return 'There was a soft rustling in the trees. The moon climbed higher in the sky. Something wonderful was about to happen.';
};

const EDUCATIONAL_FALLBACK = (lessonName: string): string =>
  `The character looked around and thought carefully. There was something important to discover about ${lessonName}. With a curious smile, they began to explore.`;

/**
 * Node 5/6 — HALLUCINATION GUARD
 *
 * Validates the generated segment for:
 * - Character consistency
 * - Age appropriateness
 * - Tone matching drift/engagement target
 * - No continuity breaks
 * - (Educational) Lesson concept accuracy
 *
 * Returns corrected segment or fallback after 2 failures.
 */
export async function runHallucinationGuard(
  segment: string,
  state: GraphState,
  guardFailures: number,
): Promise<GuardResult> {
  // After 2 failures, use fallback template
  if (guardFailures >= 2) {
    const fallback =
      state.mode === 'bedtime'
        ? BEDTIME_FALLBACK(state.drift_score)
        : EDUCATIONAL_FALLBACK(state.lesson_name);
    return { passed: false, segment: fallback, issues: ['Fallback template used after 2 guard failures'] };
  }

  const characterList = Object.values(state.characters)
    .map((c) => `${c.name}: ${c.description}, last at ${c.location}`)
    .join('\n') || 'No characters established yet';

  const modeContext =
    state.mode === 'bedtime'
      ? `Drift score: ${state.drift_score}/100 (higher = closer to sleep). Expected tone: ${
          state.drift_score > 75 ? 'very quiet and still' :
          state.drift_score > 50 ? 'softening, winding down' :
          state.drift_score > 25 ? 'warm and settling' : 'engaging and active'
        }.`
      : `Engagement score: ${state.engagement_score}/100. Lesson: ${state.lesson_name}. The concept must appear accurately and naturally.`;

  const prompt = `You are a quality guard for a children's story. Review this story segment and either APPROVE it or CORRECT it.

CHILD AGE: ${state.childProfile.age}
${modeContext}

ESTABLISHED CHARACTERS:
${characterList}

STORY CONTEXT (last 200 chars):
${state.story_context.slice(-200) || 'Story just started'}

SEGMENT TO REVIEW:
"${segment}"

CHECK FOR:
1. Character consistency — names, traits, locations match what's established
2. Age appropriateness — vocabulary and content suitable for age ${state.childProfile.age}
3. Tone matches the current score level
4. No sudden continuity breaks or impossible events
${state.mode === 'educational' ? `5. Lesson concept "${state.lesson_name}" represented accurately if present` : ''}

If the segment passes ALL checks, respond with exactly:
PASS
"<original segment unchanged>"

If it fails any check, respond with exactly:
FAIL
"<corrected segment>"
<one line explaining what was wrong>`;

  try {
    const response = await client.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 400,
      messages: [{ role: 'user', content: prompt }],
    });

    const text = (response.content[0] as { type: string; text: string }).text.trim();
    const lines = text.split('\n').filter((l) => l.trim());

    const verdict = lines[0]?.trim().toUpperCase();
    // Extract quoted segment
    const quotedMatch = text.match(/"([^"]+)"/);
    const resultSegment = quotedMatch ? quotedMatch[1] : segment;

    if (verdict === 'PASS') {
      return { passed: true, segment: resultSegment };
    } else {
      const issues = lines.slice(2).join(' ');
      return { passed: false, segment: resultSegment, issues: [issues] };
    }
  } catch (err) {
    // Guard API failure — pass through original
    console.warn('⚠️ Hallucination guard API error, passing through:', err);
    return { passed: true, segment };
  }
}
