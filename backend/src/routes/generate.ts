import { Router, Response } from 'express';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import axios from 'axios';
import Anthropic from '@anthropic-ai/sdk';

const router = Router();
const claude = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

interface ChildProfile {
  childId: string;
  name: string;
  age: number;
  storytellingTone: string;
  parentPrompt: string;
  initialState: string;
  targetDuration?: number;   // minutes — 10 short / 15 medium / 20 long
}

// Each paragraph is ~60 words narrated at ~120 wpm = ~30 seconds.
function paragraphCountForDuration(minutes: number): number {
  return Math.round((minutes * 60) / 30);
}

// ── POST /api/generate/story ──────────────────────────────────────────────────

router.post('/story', async (req: AuthRequest, res: Response) => {
  try {
    const { profile } = req.body as { profile: ChildProfile };

    if (!profile || !profile.name || !profile.parentPrompt) {
      return res.status(400).json({ error: 'Invalid profile data' });
    }

    if (!process.env.ANTHROPIC_API_KEY) {
      return res.status(500).json({ error: 'Anthropic API key not configured' });
    }

    const paragraphCount = paragraphCountForDuration(profile.targetDuration ?? 15);
    console.log(`📖 Generating story for: ${profile.name} | duration: ${profile.targetDuration ?? 15} min | paragraphs: ${paragraphCount}`);

    let childData = null;
    if (profile.childId) {
      childData = await prisma.child.findUnique({
        where: { id: profile.childId },
        include: { preferences: true },
      });
    }

    const childPersonality = childData?.preferences?.personality || '';
    const childMedia      = childData?.preferences?.favoriteMedia || '';

    const storyPrompt = `You are a bedtime story narrator. Create a calming, soothing bedtime story told in third person.

Theme/idea: ${profile.parentPrompt}
Tone: ${profile.storytellingTone}
Target age: ${profile.age}
${childPersonality ? `Child's personality (use to tailor themes, NOT to address child): ${childPersonality}` : ''}
${childMedia ? `Child's interests (weave into plot naturally): ${childMedia}` : ''}

IMPORTANT RULES:
- Do NOT address or mention the child by name. Do NOT use "${profile.name}" in the story.
- Tell a story about characters, animals, or magical beings — NOT about the child.
- Use third person narration ("the little fox walked...", "she whispered...")
- The story should gradually slow down in pace and become dreamier as it progresses.
- Write EXACTLY ${paragraphCount} paragraphs. Each paragraph is exactly 2-3 short sentences (~60 words total).
- Keep sentences short and simple — this will be displayed as subtitles and narrated aloud.
- The story must have a complete arc: opening, build-up, gentle climax, and a slow dreamy resolution.

Format: Return ONLY the story paragraphs, separated by double line breaks. No titles, no "The End".`;

    const storyResp = await claude.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 8192,
      messages: [{ role: 'user', content: storyPrompt }],
    });
    const story = (storyResp.content[0] as { type: string; text: string }).text.trim();
    console.log(`✅ Story generated (${story.length} chars)`);

    // ── Image prompts (5 scenes for StoryPlaybackView backgrounds) ────────────
    let imagePrompts: any[] = [];
    try {
      console.log('🎨 Generating image prompts...');

      const imagePromptText = `Based on this bedtime story, create exactly 5 image prompts for key scenes.

Story:
${story}

Style: dreamy digital painting, soft glowing lighting, cinematic wide shot, children illustration style, no text

Return ONLY a valid JSON array, no markdown, no code blocks:
[{"scene":"opening","prompt":"..."},{"scene":"middle1","prompt":"..."},{"scene":"middle2","prompt":"..."},{"scene":"climax","prompt":"..."},{"scene":"ending","prompt":"..."}]

Each prompt must be a single line. Be very descriptive and visual.`;

      const imgResp = await claude.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 1024,
        messages: [{ role: 'user', content: imagePromptText }],
      });
      let text = (imgResp.content[0] as { type: string; text: string }).text;
      text = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
      text = text.replace(/\n/g, ' ').replace(/\r/g, '').replace(/\s+/g, ' ');
      imagePrompts = JSON.parse(text);
      console.log(`✅ Image prompts generated: ${imagePrompts.length}`);
    } catch (err: any) {
      console.warn('⚠️ Image prompt generation failed:', err.message);
    }

    res.json({ story, imagePrompts, modelUsed: 'claude-sonnet-4-5' });

  } catch (error: any) {
    console.error('❌ Story generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate story', details: error.message });
  }
});

// ── POST /api/generate/image ──────────────────────────────────────────────────
// Uses Fal.ai Flux Schnell (same pipeline as the live story-graph images).

router.post('/image', async (req: AuthRequest, res: Response) => {
  try {
    const { prompt } = req.body;
    if (!prompt) return res.status(400).json({ error: 'Prompt is required' });

    const apiKey = process.env.FAL_API_KEY;
    if (!apiKey) return res.status(500).json({ error: 'FAL_API_KEY not configured' });

    console.log('🎨 Generating image via Fal.ai Flux Schnell...');

    // Submit to Fal.ai queue
    const submitResp = await axios.post(
      'https://queue.fal.run/fal-ai/flux/schnell',
      {
        prompt: `${prompt}, dreamy digital painting, soft glowing lighting, cinematic wide shot, children illustration style, no text`,
        image_size: 'landscape_4_3',
        num_inference_steps: 4,
        num_images: 1,
        enable_safety_checker: true,
      },
      { headers: { Authorization: `Key ${apiKey}`, 'Content-Type': 'application/json' }, timeout: 30000 },
    );

    const requestId = submitResp.data?.request_id;

    // Poll for result
    let imageUrl = '';
    for (let i = 0; i < 20; i++) {
      await new Promise(r => setTimeout(r, 2000));
      try {
        const poll = await axios.get(
          `https://queue.fal.run/fal-ai/flux/schnell/requests/${requestId}`,
          { headers: { Authorization: `Key ${apiKey}` } },
        );
        if (poll.data?.status === 'COMPLETED') {
          imageUrl = poll.data?.output?.images?.[0]?.url ?? poll.data?.images?.[0]?.url ?? '';
          break;
        }
        if (poll.data?.status === 'FAILED') break;
      } catch { /* transient */ }
    }

    if (!imageUrl) throw new Error('Fal.ai image generation timed out or failed');

    console.log('✅ Image generated');
    res.json({ imageUrl });

  } catch (error: any) {
    console.error('❌ Image generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate image', details: error.message });
  }
});

export default router;
