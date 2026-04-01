import { Router, Response } from 'express';
import { AuthRequest } from '../middleware/auth';
import { Child } from '../models/Child';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
import { v4 as uuid } from 'uuid';
import Anthropic from '@anthropic-ai/sdk';
import { fal } from '@fal-ai/client';
import { uploadToR2 } from '../lib/r2';

// Configure fal client
fal.config({ credentials: process.env.FAL_API_KEY ?? '' });

const router = Router();
const claude = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const UPLOADS_DIR = path.join(process.cwd(), 'uploads', 'story-images');
if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR, { recursive: true });

interface ChildProfile {
  childId: string;
  name: string;
  age: number;
  storytellingTone: string;
  parentPrompt: string;
  initialState: string;
  targetDuration?: number;
}

function paragraphCountForDuration(minutes: number): number {
  return Math.round((minutes * 60) / 30);
}

// ── fal.ai image generation with advanced drift adaptation ───────────────────
//
// Reference strategy:
//   Paragraph 1: Flux Schnell text-to-image — establishes art style
//   Paragraph 2: Flux Dev image-to-image with paragraph-1 FAL URL (style anchor)
//   Paragraph 3+: Flux Dev image-to-image with previous paragraph FAL URL
//                 + dynamic strength based on drift score (vitals + eyes)
//
// FAL CDN URLs returned by each call are stored temporarily for next iteration.

const FAL_STYLE_SUFFIX =
  "children's storybook illustration, painterly watercolor style, " +
  'no text, no words, no letters, soft edges, landscape 4:3 aspect ratio';

function driftPalette(driftPercent: number): string {
  if (driftPercent < 0.33) return 'warm golden light, soft amber tones, cozy and inviting';
  if (driftPercent < 0.66) return 'soft twilight, muted purples and blues, dreamy atmosphere';
  return 'cool moonlit night, deep indigo, gentle silver glow, tranquil';
}

function strengthForDrift(driftPercent: number): number {
  // Scene evolves more freely early in the story (lower strength),
  // stays closer to reference as the story winds down (higher strength).
  // This creates visual consistency that mirrors the child's drowsiness progression.
  return Math.min(0.88, 0.75 + driftPercent * 0.13);
}

async function storeR2(falUrl: string): Promise<string> {
  const isJpeg = !falUrl.includes('.png');
  const [ext, ct] = isJpeg ? ['jpg', 'image/jpeg'] : ['png', 'image/png'];
  const resp = await axios.get(falUrl, { responseType: 'arraybuffer', timeout: 20000 });
  return uploadToR2(Buffer.from(resp.data), ext, ct);
}

/**
 * Generates one paragraph image and returns both the permanent R2 URL
 * and the ephemeral FAL CDN URL (needed as a reference for the next call).
 *
 * @param firstFalUrl  FAL CDN URL of paragraph 1 — style anchor for all images
 * @param prevFalUrl   FAL CDN URL of the immediately preceding paragraph
 */
async function generateParagraphImage(
  paragraphText: string,
  storyContext:  string,
  driftPercent:  number,
  firstFalUrl?:  string,   // undefined for paragraph 1
  prevFalUrl?:   string,   // undefined for paragraph 1
): Promise<{ r2Url: string; falUrl: string }> {
  if (!process.env.FAL_API_KEY) throw new Error('FAL_API_KEY not configured');

  const palette = driftPalette(driftPercent);
  const basePrompt =
    `${paragraphText.slice(0, 300)}. ` +
    `${storyContext ? `Context: ${storyContext.slice(0, 150)}. ` : ''}` +
    `${palette}, ${FAL_STYLE_SUFFIX}`;

  let falUrl: string;

  if (!firstFalUrl) {
    // ── Paragraph 1: text-to-image (Flux Schnell) ─────────────────────────────
    console.log('🎨 Para 1 — Flux Schnell text-to-image');
    const result = await fal.subscribe('fal-ai/flux/schnell', {
      input: {
        prompt:               basePrompt,
        image_size:           'landscape_4_3',
        num_inference_steps:  4,
        num_images:           1,
        enable_safety_checker: true,
        output_format:        'jpeg',
      },
    });
    falUrl = (result.data as any).images?.[0]?.url ?? '';

  } else if (!prevFalUrl || prevFalUrl === firstFalUrl) {
    // ── Paragraph 2: style anchor — image-to-image with paragraph-1 URL ──────
    console.log('🎨 Para 2 — Flux Dev img2img (style anchor)');
    const result = await fal.subscribe('fal-ai/flux/dev/image-to-image', {
      input: {
        prompt:               basePrompt,
        image_url:            firstFalUrl,
        strength:             0.80,
        num_inference_steps:  28,
        guidance_scale:       3.5,
        num_images:           1,
        enable_safety_checker: true,
        output_format:        'jpeg',
      },
    });
    falUrl = (result.data as any).images?.[0]?.url ?? '';

  } else {
    // ── Paragraph 3+: scene continuity with DYNAMIC strength based on drift ──
    const strength = strengthForDrift(driftPercent);
    const anchored = `${basePrompt} Maintain the exact same storybook art style as the opening illustration.`;
    console.log(`🎨 Para N — Flux Dev img2img (continuity, strength ${strength.toFixed(2)}, drift ${(driftPercent * 100).toFixed(0)}%)`);
    const result = await fal.subscribe('fal-ai/flux/dev/image-to-image', {
      input: {
        prompt:               anchored,
        image_url:            prevFalUrl,
        strength,
        num_inference_steps:  28,
        guidance_scale:       3.5,
        num_images:           1,
        enable_safety_checker: true,
        output_format:        'jpeg',
      },
    });
    falUrl = (result.data as any).images?.[0]?.url ?? '';
  }

  if (!falUrl) throw new Error('No image URL returned from fal.ai');

  const r2Url = await storeR2(falUrl);
  return { r2Url, falUrl };
}

// ── ElevenLabs paragraph audio ────────────────────────────────────────────────

async function generateParagraphAudio(text: string, driftPercent: number): Promise<string> {
  const apiKey  = process.env.ELEVENLABS_API_KEY;
  const voiceId = process.env.ELEVENLABS_VOICE_ID || 'XrExE9yKIg1WjnnlVkGX'; // Matilda
  if (!apiKey) throw new Error('ELEVENLABS_API_KEY not configured');

  const speed      = 0.55 - driftPercent * 0.17;
  const stability  = 0.82 + driftPercent * 0.15;
  const style      = Math.max(0, 0.15 - driftPercent * 0.15);

  const resp = await axios.post(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      text,
      model_id: 'eleven_turbo_v2_5',
      voice_settings: { stability, similarity_boost: 0.80, style, use_speaker_boost: false },
      speed,
    },
    {
      headers: { 'xi-api-key': apiKey, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
      responseType: 'arraybuffer',
      timeout: 30_000,
    },
  );

  const filename = `${uuid()}.mp3`;
  fs.writeFileSync(path.join(UPLOADS_DIR, filename), Buffer.from(resp.data));
  return `/images/${filename}`;
}

// ── Concurrency helper ────────────────────────────────────────────────────────

async function pMap<T, R>(items: T[], fn: (item: T, index: number) => Promise<R>, concurrency = 5): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let idx = 0;
  async function worker() {
    while (idx < items.length) { const i = idx++; results[i] = await fn(items[i], i); }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, worker));
  return results;
}

// ── In-memory image progress ──────────────────────────────────────────────────
const imageProgress = new Map<string, string[]>();

// ── POST /api/generate/story ──────────────────────────────────────────────────

router.post('/story', async (req: AuthRequest, res: Response) => {
  try {
    const { profile } = req.body as { profile: ChildProfile };
    if (!profile?.name || !profile?.parentPrompt) return res.status(400).json({ error: 'Invalid profile data' });
    if (!process.env.ANTHROPIC_API_KEY)  return res.status(500).json({ error: 'Anthropic API key not configured' });
    if (!process.env.ELEVENLABS_API_KEY) return res.status(500).json({ error: 'ElevenLabs API key not configured' });

    const paragraphCount = paragraphCountForDuration(profile.targetDuration ?? 15);
    console.log(`📖 ${profile.name} | ${profile.targetDuration ?? 15} min | ${paragraphCount} paragraphs`);

    let childPersonality = '', childMedia = '';
    if (profile.childId) {
      const childData = await Child.findById(profile.childId);
      childPersonality = childData?.preferences?.personality || '';
      childMedia       = childData?.preferences?.favoriteMedia || '';
    }

    // Phase 1: story text (Claude)
    const storyPrompt =
      `You are a bedtime story narrator. Create a calming, soothing bedtime story told in third person.\n\n` +
      `Theme/idea: ${profile.parentPrompt}\nTone: ${profile.storytellingTone}\nTarget age: ${profile.age}\n` +
      (childPersonality ? `Child's personality (tailor themes, do NOT address child): ${childPersonality}\n` : '') +
      (childMedia       ? `Child's interests (weave into plot naturally): ${childMedia}\n` : '') +
      `\nIMPORTANT RULES:\n` +
      `- Do NOT use the name "${profile.name}" in the story.\n` +
      `- Tell a story about characters, animals, or magical beings — not about the child.\n` +
      `- Third-person narration only.\n` +
      `- The story gradually slows, becomes dreamier as it progresses.\n` +
      `- Write EXACTLY ${paragraphCount} paragraphs. Each paragraph is 2-3 short sentences (~60 words).\n` +
      `- Complete arc: opening → build-up → gentle climax → slow dreamy resolution.\n\n` +
      `Format: ONLY the story paragraphs, separated by double line breaks. No titles, no "The End".`;

    const storyResp = await claude.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 8192,
      messages: [{ role: 'user', content: storyPrompt }],
    });
    const storyText  = (storyResp.content[0] as { type: string; text: string }).text.trim();
    const paragraphs = storyText.split(/\n\n+/).map(p => p.trim()).filter(Boolean);
    const total      = Math.max(1, paragraphs.length - 1);
    const storyContext = `${profile.parentPrompt} — ${profile.storytellingTone} tone`;
    console.log(`✅ Story text (${storyText.length} chars, ${paragraphs.length} paragraphs)`);

    // ── Set up image job immediately after story text — don't wait for audio ──
    const tempStoryId = uuid();
    const pending = new Array(paragraphs.length).fill('');
    imageProgress.set(tempStoryId, pending);

    // Phase 2 + 3: audio and images run concurrently
    // Image 0 starts RIGHT NOW so it's ready within ~5s when the app opens the story.
    // Remaining images follow sequentially, each referencing the previous for style consistency.
    console.log(`🎨 Starting fal.ai image generation for ${tempStoryId}…`);
    const imageGenPromise = (async () => {
      let firstFalUrl = '';
      let prevFalUrl = '';
      
      for (let i = 0; i < paragraphs.length; i++) {
        try {
          const { r2Url, falUrl } = await generateParagraphImage(
            paragraphs[i],
            storyContext,
            i / total,
            firstFalUrl || undefined,
            prevFalUrl || undefined
          );
          
          pending[i] = r2Url;
          if (i === 0) firstFalUrl = falUrl;
          prevFalUrl = falUrl;
          
          console.log(`  🖼  Image ${i + 1}/${paragraphs.length}: ${r2Url} (drift ${((i / total) * 100).toFixed(0)}%)`);
        } catch (err: any) {
          console.warn(`  ⚠️  Image ${i + 1} failed: ${err.message}`);
        }
      }
      console.log(`✅ All images done for ${tempStoryId}`);
      setTimeout(() => imageProgress.delete(tempStoryId), 60 * 60 * 1000);
    })();

    // Phase 2: ElevenLabs audio (concurrency 3) — runs in parallel with images
    console.log(`🔊 Generating ${paragraphs.length} audio clips…`);
    const audioUrls = await pMap(paragraphs, async (para, i) => {
      try {
        const url = await generateParagraphAudio(para, i / total);
        console.log(`  🔊 Audio ${i + 1}/${paragraphs.length}: ${url}`);
        return url;
      } catch (err: any) {
        console.warn(`  ⚠️  Audio ${i + 1} failed: ${err.message}`);
        return '';
      }
    }, 3);
    console.log(`✅ Audio: ${audioUrls.filter(Boolean).length}/${paragraphs.length}`);

    // Fire-and-forget the remaining image work (imageGenPromise keeps running in background)
    imageGenPromise.catch(() => {});

    return res.json({ story: storyText, generatedImages: [], audioUrls, imageJobId: tempStoryId, modelUsed: 'claude-sonnet-4-5' });
  } catch (error: any) {
    console.error('❌ Story generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate story', details: error.message });
  }
});

// ── GET /api/generate/story-images/:jobId ─────────────────────────────────────

router.get('/story-images/:jobId', async (req: AuthRequest, res: Response) => {
  const images = imageProgress.get(req.params.jobId);
  if (!images) return res.status(404).json({ error: 'Job not found' });
  return res.json({ images, complete: images.every(u => u !== '') });
});

// ── POST /api/generate/paragraph-image ───────────────────────────────────────

router.post('/paragraph-image', async (req: AuthRequest, res: Response) => {
  try {
    const { paragraphText, storyContext, paragraphIndex, totalParagraphs } = req.body as {
      paragraphText: string; storyContext: string; paragraphIndex: number; totalParagraphs: number;
    };
    if (!paragraphText) return res.status(400).json({ error: 'paragraphText required' });
    const drift = totalParagraphs > 1 ? paragraphIndex / (totalParagraphs - 1) : 0;
    const { r2Url } = await generateParagraphImage(paragraphText, storyContext ?? '', drift);
    return res.json({ imageUrl: r2Url });
  } catch (error: any) {
    console.error('❌ Paragraph image error:', error.message);
    res.status(500).json({ error: 'Failed to generate image', details: error.message });
  }
});

// ── POST /api/generate/image (legacy) ────────────────────────────────────────

router.post('/image', async (req: AuthRequest, res: Response) => {
  try {
    const { prompt } = req.body;
    if (!prompt) return res.status(400).json({ error: 'Prompt is required' });
    const { r2Url } = await generateParagraphImage(prompt, '', 0.5);
    return res.json({ imageUrl: r2Url });
  } catch (error: any) {
    console.error('❌ Image generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate image', details: error.message });
  }
});

// ── POST /api/generate/minigame ───────────────────────────────────────────────

router.post('/minigame', async (req: AuthRequest, res: Response) => {
  try {
    const { paragraphText, storyContext, childAge, paragraphIndex } = req.body as {
      paragraphText: string; storyContext: string; childAge?: number; paragraphIndex?: number;
    };
    if (!paragraphText) return res.status(400).json({ error: 'paragraphText required' });

    const age  = childAge    ?? 6;
    const pIdx = paragraphIndex ?? 0;

    const prompt =
      `You are designing a fun, age-appropriate minigame for a child aged ${age} inside a bedtime story.\n\n` +
      `STORY CONTEXT: ${(storyContext ?? '').slice(0, 200)}\n` +
      `CURRENT PARAGRAPH:\n"${paragraphText.slice(0, 400)}"\n\n` +
      `Choose ONE minigame type. Rotate types for variety (this is paragraph ${pIdx}):\n` +
      `- "drawing": child draws something from the story\n` +
      `- "voice": child says a word/sound aloud\n` +
      `- "shape_sorting": child drags shapes to correct slots\n` +
      `- "multiple_choice": child picks the correct answer (3 options)\n\n` +
      `Return ONLY valid JSON, no markdown:\n` +
      `{"type":"drawing"|"voice"|"shape_sorting"|"multiple_choice","narratorPrompt":"max 12 words","drawingTheme":"...","drawingDarkBackground":true,"voiceTarget":"word","voiceHint":"question","choices":[{"id":"a","label":"...","emoji":"🌟","isCorrect":true},{"id":"b","label":"...","emoji":"🌙","isCorrect":false},{"id":"c","label":"...","emoji":"⭐","isCorrect":false}],"shapes":[{"id":"s1","shape":"circle","color":"#FF6B6B","targetSlotId":"slot_circle"},{"id":"s2","shape":"square","color":"#4ECDC4","targetSlotId":"slot_square"},{"id":"s3","shape":"triangle","color":"#45B7D1","targetSlotId":"slot_triangle"}],"timeoutSeconds":30}\n\nOnly include fields for the chosen type.`;

    let trigger: any;
    try {
      const response = await claude.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 512,
        messages: [{ role: 'user', content: prompt }],
      });
      const text    = (response.content[0] as { type: string; text: string }).text;
      const cleaned = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
      trigger = JSON.parse(cleaned);
      if (!trigger.type || !trigger.narratorPrompt) throw new Error('Missing required fields');
    } catch {
      const types = ['multiple_choice', 'drawing', 'voice', 'shape_sorting'] as const;
      const type  = types[pIdx % 4];
      trigger = type === 'drawing'
        ? { type: 'drawing', narratorPrompt: 'Draw what you see in the story!', drawingTheme: 'a magical scene', drawingDarkBackground: true, timeoutSeconds: 40 }
        : type === 'voice'
        ? { type: 'voice', narratorPrompt: 'Can you say it out loud?', voiceTarget: 'magic', voiceHint: 'Say "magic"!', timeoutSeconds: 20 }
        : type === 'shape_sorting'
        ? { type: 'shape_sorting', narratorPrompt: 'Put the shapes where they belong!',
            shapes: [{ id: 's1', shape: 'circle', color: '#FF6B6B', targetSlotId: 'slot_circle' }, { id: 's2', shape: 'square', color: '#4ECDC4', targetSlotId: 'slot_square' }, { id: 's3', shape: 'triangle', color: '#45B7D1', targetSlotId: 'slot_triangle' }], timeoutSeconds: 35 }
        : { type: 'multiple_choice', narratorPrompt: 'Quick question — what do you think?',
            choices: [{ id: 'a', label: 'In the forest', emoji: '🌲', isCorrect: true }, { id: 'b', label: 'In the ocean', emoji: '🌊', isCorrect: false }, { id: 'c', label: 'In the sky', emoji: '☁️', isCorrect: false }], timeoutSeconds: 25 };
    }

    return res.json(trigger);
  } catch (error: any) {
    console.error('❌ Minigame generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate minigame', details: error.message });
  }
});

export default router;
