import Anthropic from '@anthropic-ai/sdk';
import { BedtimeState, EducationalState, NarrativeStrategy, EducationalStrategyResult } from '../types';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// ── Bedtime story generation ───────────────────────────────────────────────────

export async function generateBedtimeSegment(
  state: BedtimeState,
  strategy: NarrativeStrategy,
): Promise<string> {
  const { childProfile, story_context, characters, arc_position, drift_score } = state;

  const characterSummary = Object.values(characters)
    .map((c) => `${c.name}: ${c.description}. Last seen: ${c.lastAction} at ${c.location}`)
    .join('\n');

  const prompt = `You are a bedtime story narrator creating an adaptive, real-time story for a child.

CHILD PROFILE:
- Age: ${childProfile.age}
- Favourite animal: ${childProfile.favoriteAnimal || 'not specified'}
- Favourite place: ${childProfile.favoritePlace || 'not specified'}
- Tonight's mood: ${childProfile.tonightsMood || 'normal'}

STORY STATE:
- Arc position: ${arc_position}
- Drift score: ${drift_score}/100 (higher = closer to sleep)
- Characters established:
${characterSummary || '  None yet — this is the opening.'}

STORY SO FAR (last 300 chars):
${story_context.slice(-300) || '  Story has not started yet.'}

NARRATIVE STRATEGY — ${strategy.strategy.toUpperCase()}:
${strategy.prompt_directive}

RULES:
- Generate exactly the next 60 seconds of story narration (roughly 3-5 sentences).
- Maintain perfect character consistency with what's established.
- Third-person narration. Do NOT address the child directly or use their name.
- Age-appropriate vocabulary for a ${childProfile.age}-year-old.
- DO NOT summarise or repeat what came before — continue naturally.
- No titles, no "Chapter X", no stage directions. Pure story prose only.`;

  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 300,
    messages: [{ role: 'user', content: prompt }],
  });

  return (response.content[0] as { type: string; text: string }).text.trim();
}

// ── Educational story generation ───────────────────────────────────────────────

export async function generateEducationalSegment(
  state: EducationalState,
  strategy: EducationalStrategyResult,
): Promise<string> {
  const {
    childProfile,
    story_context,
    characters,
    lesson_name,
    lesson_description,
    lesson_plan,
    concepts_introduced,
    engagement_score,
  } = state;

  const characterSummary = Object.values(characters)
    .map((c) => `${c.name}: ${c.description}. Last seen: ${c.lastAction} at ${c.location}`)
    .join('\n');

  const prompt = `You are an educational story narrator creating an adaptive learning story for a child.

CHILD PROFILE:
- Age: ${childProfile.age}
- Favourite character: ${childProfile.favoriteCharacter || 'a curious animal'}
- Preferred world: ${childProfile.preferredWorld || 'forest'}

LESSON:
- Name: ${lesson_name}
- Description: ${lesson_description}
- Character challenge: ${lesson_plan?.character_challenge || 'character naturally encounters the concept'}
- Concepts already introduced: ${concepts_introduced.join(', ') || 'none yet'}

STORY STATE:
- Engagement score: ${engagement_score}/100
- Characters:
${characterSummary || '  None yet — this is the opening.'}

STORY SO FAR (last 300 chars):
${story_context.slice(-300) || '  Story has not started yet.'}

EDUCATIONAL STRATEGY — ${strategy.strategy.toUpperCase()}:
${strategy.prompt_directive}
${strategy.next_concept ? `Next concept to weave in: "${strategy.next_concept}"` : ''}

RULES:
- Generate exactly the next 45 seconds of story narration (roughly 3-4 sentences).
- The lesson concept MUST emerge through story action — NEVER explain it directly.
- Let the character USE the concept naturally; the child observes and absorbs.
- Age-appropriate vocabulary for a ${childProfile.age}-year-old.
- Maintain perfect character consistency.
- If this is an interactive moment, end with a question or pause for the child.
- Third-person narration. Pure story prose only — no titles, no explanations.`;

  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 300,
    messages: [{ role: 'user', content: prompt }],
  });

  return (response.content[0] as { type: string; text: string }).text.trim();
}

// ── Resolution segment (bedtime session end) ───────────────────────────────────

export async function generateResolutionSegment(state: BedtimeState): Promise<string> {
  const { childProfile, story_context, characters } = state;
  const characterSummary = Object.values(characters)
    .map((c) => `${c.name}`)
    .join(', ');

  const prompt = `You are closing a bedtime story. The child is almost asleep.

Characters: ${characterSummary || 'the story characters'}
Story so far (last 200 chars): ${story_context.slice(-200)}

Write the final 3 sentences of this story. The protagonist finds exactly what they were seeking. The world goes completely still. The story breathes its last sentence — very short, very quiet, very peaceful. Use extremely short sentences. Maximum 60 words total.`;

  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 150,
    messages: [{ role: 'user', content: prompt }],
  });

  return (response.content[0] as { type: string; text: string }).text.trim();
}

// ── Lesson completion segment (educational session end) ────────────────────────

export async function generateLessonCompletionSegment(state: EducationalState): Promise<string> {
  const { childProfile, lesson_name, characters, story_context } = state;
  const characterSummary = Object.values(characters)
    .map((c) => c.name)
    .join(', ');

  const prompt = `You are completing an educational story for a child aged ${childProfile.age}.

Lesson completed: ${lesson_name}
Characters: ${characterSummary || 'the story characters'}
Story so far (last 200 chars): ${story_context.slice(-200)}

Write the final 3-4 sentences. The character successfully uses the concept learned to solve the problem. End with a warm, satisfying celebration moment — joyful but gentle. Pure story prose, no explanations. Maximum 80 words.`;

  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 200,
    messages: [{ role: 'user', content: prompt }],
  });

  return (response.content[0] as { type: string; text: string }).text.trim();
}
