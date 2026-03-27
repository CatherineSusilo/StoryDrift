import Anthropic from '@anthropic-ai/sdk';
import { LessonPlan, ChildProfile } from '../types';

/**
 * LESSON PLANNER — runs once at session start (educational mode).
 * Uses Claude to create a structured lesson arc from the lesson brief.
 */
export async function planLesson(
  lessonName: string,
  lessonDescription: string,
  childProfile: ChildProfile,
): Promise<LessonPlan> {
  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

  const prompt = `You are an expert children's educational content designer.

Create a structured lesson arc for an interactive educational story.

LESSON NAME: ${lessonName}
LESSON DESCRIPTION: ${lessonDescription}
CHILD AGE: ${childProfile.age}
FAVOURITE CHARACTER: ${childProfile.favoriteCharacter || 'a curious animal'}
PREFERRED WORLD: ${childProfile.preferredWorld || 'forest'}

Design the lesson so the concept emerges NATURALLY through story — the character encounters and uses the concept without the narrator ever explaining it directly.

Return ONLY valid JSON, no markdown, no explanation:
{
  "concept_sequence": ["step1 description", "step2 description", "step3 description"],
  "character_challenge": "How the character naturally encounters the core concept in the story world",
  "reinforcement_moments": ["checkpoint 1 description", "checkpoint 2 description", "checkpoint 3 description"],
  "success_condition": "What observable story moment demonstrates the child has absorbed the concept"
}`;

  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 1024,
    messages: [{ role: 'user', content: prompt }],
  });

  const text = (response.content[0] as { type: string; text: string }).text;

  try {
    const cleaned = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
    return JSON.parse(cleaned) as LessonPlan;
  } catch {
    // Fallback minimal plan
    return {
      concept_sequence: ['Introduce the concept', 'Explore the concept', 'Apply the concept'],
      character_challenge: `The character encounters situations that require understanding ${lessonName}`,
      reinforcement_moments: ['First encounter', 'Second encounter', 'Mastery moment'],
      success_condition: `Character successfully uses ${lessonName} to solve a problem`,
    };
  }
}
