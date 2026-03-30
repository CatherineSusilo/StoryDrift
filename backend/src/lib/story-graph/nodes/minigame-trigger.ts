import Anthropic from '@anthropic-ai/sdk';
import {
  MinigameTrigger,
  MinigameType,
  MinigameChoice,
  ShapeSlot,
  EducationalState,
} from '../types';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// How many segments must pass between minigames, per frequency setting
function minSegmentsBetween(frequency: string): number {
  switch (frequency) {
    case 'every_paragraph': return 1;
    case 'every_3rd':       return 3;
    case 'every_5th':       return 5;
    case 'none':
    default:                return Infinity;
  }
}

// Child is too drowsy / disengaged to participate — suppress minigames.
// Below this threshold engagement is so low the child may be drifting off.
const DRIFT_SUPPRESSION_THRESHOLD = 25;

export async function decidMinigame(
  state: EducationalState,
  segment: string,
): Promise<MinigameTrigger | null> {
  const { segments_since_last_minigame, engagement_score, lesson_name, lesson_description, childProfile } = state;

  const freq = state.minigame_frequency ?? 'every_5th';
  const minGap = minSegmentsBetween(freq);

  // frequency = none → never fire
  if (minGap === Infinity) return null;

  // Child is drifting / drowsy → suppress minigames
  if (engagement_score < DRIFT_SUPPRESSION_THRESHOLD) {
    console.log(`🎮 Minigame suppressed: engagement ${engagement_score} < ${DRIFT_SUPPRESSION_THRESHOLD} (child drifting)`);
    return null;
  }

  // Not enough segments since last minigame
  if (segments_since_last_minigame < minGap) {
    console.log(`🎮 Minigame gated: ${segments_since_last_minigame}/${minGap} segments since last (freq=${freq})`);
    return null;
  }

  console.log(`🎮 Firing minigame! engagement=${engagement_score}, segments_since_last=${segments_since_last_minigame}, freq=${freq}`);

  // Ask Claude to generate an appropriate minigame for the current story moment
  const prompt = `You are designing a fun, age-appropriate minigame for a child aged ${childProfile.age} inside an educational story.

LESSON: ${lesson_name}
LESSON DESCRIPTION: ${lesson_description}
CURRENT STORY SEGMENT:
"${segment}"

Choose ONE minigame type that fits naturally into this story moment:
- "drawing": child draws something mentioned in the segment (e.g., a sword, a star, an animal). Background goes dark.
- "voice": child says a sound or word aloud (perfect if an animal appears, or a letter/word is relevant)
- "shape_sorting": child drags shapes into correct holes (perfect for counting, sorting, patterns)
- "multiple_choice": child taps the correct answer from 3-4 options (comprehension, character ID, concept check)

Return ONLY valid JSON, no markdown:
{
  "type": "drawing" | "voice" | "shape_sorting" | "multiple_choice",
  "narratorPrompt": "Short sentence the narrator says to introduce the activity (max 15 words)",
  "drawingTheme": "what to draw (only for drawing type)",
  "drawingDarkBackground": true | false,
  "voiceTarget": "exact word/sound child should say (only for voice type)",
  "voiceHint": "Narrator question to elicit the sound (only for voice type)",
  "choices": [
    {"id": "a", "label": "option text", "emoji": "🐄", "isCorrect": false},
    {"id": "b", "label": "option text", "emoji": "🐕", "isCorrect": true},
    {"id": "c", "label": "option text", "emoji": "🐱", "isCorrect": false}
  ],
  "shapes": [
    {"id": "s1", "shape": "circle", "color": "#FF6B6B", "targetSlotId": "slot_circle"},
    {"id": "s2", "shape": "square", "color": "#4ECDC4", "targetSlotId": "slot_square"},
    {"id": "s3", "shape": "triangle", "color": "#45B7D1", "targetSlotId": "slot_triangle"}
  ],
  "timeoutSeconds": 30
}

Only include fields relevant to the chosen type. Keep it simple and directly tied to the story moment.`;

  try {
    const response = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 512,
      messages: [{ role: 'user', content: prompt }],
    });

    const text = (response.content[0] as { type: string; text: string }).text;
    const cleaned = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
    const parsed = JSON.parse(cleaned) as MinigameTrigger;

    // Validate required fields
    if (!parsed.type || !parsed.narratorPrompt) return null;

    return parsed;
  } catch (err) {
    console.warn('⚠️ Minigame trigger generation failed:', err);
    // Return a simple fallback minigame so the lesson stays interactive
    return buildFallbackMinigame(state, segment);
  }
}

function buildFallbackMinigame(state: EducationalState, segment: string): MinigameTrigger {
  const { lesson_name } = state;

  // Rotate through types based on segment count for variety
  const types: MinigameType[] = ['multiple_choice', 'drawing', 'voice', 'shape_sorting'];
  const type = types[state.segments.length % types.length];

  if (type === 'multiple_choice') {
    return {
      type: 'multiple_choice',
      narratorPrompt: `Quick question! Can you help me?`,
      choices: [
        { id: 'a', label: `Yes, ${lesson_name}!`, emoji: '✅', isCorrect: true },
        { id: 'b', label: 'I\'m not sure', emoji: '🤔', isCorrect: false },
        { id: 'c', label: 'Skip for now', emoji: '⏭️', isCorrect: false },
      ],
      timeoutSeconds: 25,
    };
  }

  if (type === 'drawing') {
    return {
      type: 'drawing',
      narratorPrompt: 'Draw what you see in the story!',
      drawingTheme: 'what you imagine in this moment',
      drawingDarkBackground: false,
      timeoutSeconds: 40,
    };
  }

  if (type === 'voice') {
    return {
      type: 'voice',
      narratorPrompt: 'Say it out loud!',
      voiceTarget: lesson_name.split(' ')[0].toLowerCase(),
      voiceHint: `Can you say "${lesson_name.split(' ')[0]}"?`,
      timeoutSeconds: 20,
    };
  }

  // shape_sorting
  return {
    type: 'shape_sorting',
    narratorPrompt: 'Put the shapes where they belong!',
    shapes: [
      { id: 's1', shape: 'circle', color: '#FF6B6B', targetSlotId: 'slot_circle' },
      { id: 's2', shape: 'square', color: '#4ECDC4', targetSlotId: 'slot_square' },
      { id: 's3', shape: 'triangle', color: '#45B7D1', targetSlotId: 'slot_triangle' },
    ],
    timeoutSeconds: 35,
  };
}
