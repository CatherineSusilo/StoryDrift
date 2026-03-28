import { Router, Response } from 'express';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
import { v4 as uuid } from 'uuid';
import Anthropic from '@anthropic-ai/sdk';

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

// ── Gemini 2.5 Flash image generation ────────────────────────────────────────

const GEMINI_IMAGE_MODEL = 'gemini-2.5-flash-image';
const GEMINI_IMAGE_URL   = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_IMAGE_MODEL}:generateContent`;

const delay = (ms: number) => new Promise(r => setTimeout(r, ms));

/**
 * Call Gemini image API with exponential backoff on 429 / 5xx.
 * Max 4 attempts: 0s, 8s, 16s, 32s delay between retries.
 */
async function callGeminiWithRetry(apiKey: string, body: object, attempt = 0): Promise<any> {
  try {
    return await axios.post(`${GEMINI_IMAGE_URL}?key=${apiKey}`, body, {
      headers: { 'Content-Type': 'application/json' },
      timeout: 90_000,
    });
  } catch (err: any) {
    const status = err.response?.status;
    if ((status === 429 || status >= 500) && attempt < 3) {
      const wait = 8_000 * Math.pow(2, attempt); // 8s, 16s, 32s
      console.warn(`  ⏳ Gemini ${status} — retrying in ${wait / 1000}s (attempt ${attempt + 1}/3)`);
      await delay(wait);
      return callGeminiWithRetry(apiKey, body, attempt + 1);
    }
    throw err;
  }
}

async function generateParagraphImage(
  paragraphText: string,
  storyContext: string,
  driftPercent: number,
): Promise<string> {
  const apiKey = process.env.GOOGLE_API_KEY;
  if (!apiKey) throw new Error('GOOGLE_API_KEY not configured');

  const palette =
    driftPercent < 0.33 ? 'warm golden light, soft amber tones, cozy and inviting' :
    driftPercent < 0.66 ? 'soft twilight, muted purples and blues, dreamy atmosphere' :
                          'cool moonlit night, deep indigo, gentle silver glow, tranquil';

  const prompt =
    `Children's storybook illustration. ` +
    `Overall story: ${storyContext.slice(0, 200)}. ` +
    `Current scene: ${paragraphText.slice(0, 300)}. ` +
    `Style: watercolor painting, ${palette}, soft edges, ` +
    `no text, no words, no letters, wide landscape format, 4:3 aspect ratio.`;

  const resp = await callGeminiWithRetry(apiKey, {
    contents: [{ parts: [{ text: prompt }] }],
    generationConfig: { responseModalities: ['IMAGE', 'TEXT'] },
  });

  const parts = resp.data?.candidates?.[0]?.content?.parts ?? [];
  const imgPart = parts.find((p: any) => p.inlineData);
  if (!imgPart) throw new Error('No image in Gemini response');

  const { mimeType, data: b64 } = imgPart.inlineData;
  const ext = mimeType === 'image/png' ? 'png' : mimeType === 'image/webp' ? 'webp' : 'jpg';
  const filename = `${uuid()}.${ext}`;
  fs.writeFileSync(path.join(UPLOADS_DIR, filename), Buffer.from(b64, 'base64'));
  return `/images/${filename}`;
}

// ── ElevenLabs paragraph audio generation ────────────────────────────────────

/**
 * Generates a slow, warm narration MP3 for a story paragraph.
 * Speed 0.75 → 0.55 across the story so the voice gets progressively sleepier.
 * Returns a permanent local URL, e.g. /images/abc123.mp3
 */
async function generateParagraphAudio(
  text: string,
  driftPercent: number,  // 0 (start) → 1 (end of story)
): Promise<string> {
  const apiKey  = process.env.ELEVENLABS_API_KEY;
  const voiceId = process.env.ELEVENLABS_VOICE_ID || '9BWtsMINqrJLrRacOk9x'; // Aria — warm, calm

  if (!apiKey) throw new Error('ELEVENLABS_API_KEY not configured');

  // Start at 0.75 (slow bedtime pace), slide to 0.55 by the end (very drowsy)
  const speed = 0.75 - driftPercent * 0.20;

  // Voice becomes more stable and less expressive as the story winds down
  const stability        = 0.75 + driftPercent * 0.20;
  const style            = Math.max(0, 0.25 - driftPercent * 0.25);

  const resp = await axios.post(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      text,
      model_id: 'eleven_turbo_v2_5',
      voice_settings: {
        stability,
        similarity_boost: 0.80,
        style,
        use_speaker_boost: false,
      },
      speed,
    },
    {
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
        Accept: 'audio/mpeg',
      },
      responseType: 'arraybuffer',
      timeout: 30_000,
    },
  );

  const filename = `${uuid()}.mp3`;
  fs.writeFileSync(path.join(UPLOADS_DIR, filename), Buffer.from(resp.data));
  return `/images/${filename}`;
}

// ── Concurrency helper ────────────────────────────────────────────────────────

async function pMap<T, R>(
  items: T[],
  fn: (item: T, index: number) => Promise<R>,
  concurrency = 5,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let idx = 0;
  async function worker() {
    while (idx < items.length) {
      const i = idx++;
      results[i] = await fn(items[i], i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, worker));
  return results;
}

// ── In-memory image progress store ────────────────────────────────────────────
// Maps storyId → array of image URLs ('' = still pending, filled as they complete)
const imageProgress = new Map<string, string[]>();

// ── POST /api/generate/story ──────────────────────────────────────────────────

router.post('/story', async (req: AuthRequest, res: Response) => {
  try {
    const { profile } = req.body as { profile: ChildProfile };

    if (!profile?.name || !profile?.parentPrompt) {
      return res.status(400).json({ error: 'Invalid profile data' });
    }
    if (!process.env.ANTHROPIC_API_KEY)  return res.status(500).json({ error: 'Anthropic API key not configured' });
    if (!process.env.ELEVENLABS_API_KEY) return res.status(500).json({ error: 'ElevenLabs API key not configured' });

    const paragraphCount = paragraphCountForDuration(profile.targetDuration ?? 15);
    console.log(`📖 ${profile.name} | ${profile.targetDuration ?? 15} min | ${paragraphCount} paragraphs`);

    let childData = null;
    if (profile.childId) {
      childData = await prisma.child.findUnique({
        where: { id: profile.childId },
        include: { preferences: true },
      });
    }
    const childPersonality = childData?.preferences?.personality || '';
    const childMedia       = childData?.preferences?.favoriteMedia || '';

    // ── Phase 1: story text (Claude Sonnet) ───────────────────────────────────
    const storyPrompt =
      `You are a bedtime story narrator. Create a calming, soothing bedtime story told in third person.\n\n` +
      `Theme/idea: ${profile.parentPrompt}\n` +
      `Tone: ${profile.storytellingTone}\n` +
      `Target age: ${profile.age}\n` +
      (childPersonality ? `Child's personality (tailor themes, do NOT address child): ${childPersonality}\n` : '') +
      (childMedia       ? `Child's interests (weave into plot naturally): ${childMedia}\n` : '') +
      `\nIMPORTANT RULES:\n` +
      `- Do NOT use the name "${profile.name}" in the story.\n` +
      `- Tell a story about characters, animals, or magical beings — not about the child.\n` +
      `- Third-person narration only ("the little fox walked...", "she whispered...").\n` +
      `- The story gradually slows, becomes dreamier as it progresses.\n` +
      `- Write EXACTLY ${paragraphCount} paragraphs. Each paragraph is 2-3 short sentences (~60 words).\n` +
      `- Complete arc: opening → build-up → gentle climax → slow dreamy resolution.\n\n` +
      `Format: ONLY the story paragraphs, separated by double line breaks. No titles, no "The End".`;

    const storyResp = await claude.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 8192,
      messages: [{ role: 'user', content: storyPrompt }],
    });
    const storyText = (storyResp.content[0] as { type: string; text: string }).text.trim();
    console.log(`✅ Story text (${storyText.length} chars)`);

    const paragraphs = storyText.split(/\n\n+/).map(p => p.trim()).filter(Boolean);
    const total      = Math.max(1, paragraphs.length - 1);
    const storyContext = `${profile.parentPrompt} — ${profile.storytellingTone} tone`;

    // ── Phase 2: ElevenLabs audio (concurrency 3) — run in parallel with text ─
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

    // ── Phase 3: Gemini images — background, non-blocking ─────────────────────
    // Use a temporary storyId so iOS can poll for progress
    const tempStoryId = uuid();
    const pending = new Array(paragraphs.length).fill('');
    imageProgress.set(tempStoryId, pending);

    if (process.env.GOOGLE_API_KEY) {
      console.log(`🎨 Starting background image generation for ${tempStoryId}…`);
      (async () => {
        for (let i = 0; i < paragraphs.length; i++) {
          if (i > 0) await delay(3_000);
          try {
            const url = await generateParagraphImage(paragraphs[i], storyContext, i / total);
            pending[i] = url;
            console.log(`  🖼  Image ${i + 1}/${paragraphs.length}: ${url}`);
          } catch (err: any) {
            console.warn(`  ⚠️  Image ${i + 1} failed: ${err.message}`);
          }
        }
        console.log(`✅ All images done for ${tempStoryId}`);
        // Clean up after 1 hour
        setTimeout(() => imageProgress.delete(tempStoryId), 60 * 60 * 1000);
      })();
    }

    res.json({
      story: storyText,
      generatedImages: [],    // empty — iOS polls /story-images/:id
      audioUrls,
      imageJobId: tempStoryId,
      modelUsed: 'claude-sonnet-4-5',
    });

  } catch (error: any) {
    console.error('❌ Story generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate story', details: error.message });
  }
});

// ── GET /api/generate/story-images/:jobId ─────────────────────────────────────
// Returns current image progress — iOS polls this every few seconds during playback.

router.get('/story-images/:jobId', async (req: AuthRequest, res: Response) => {
  const images = imageProgress.get(req.params.jobId);
  if (!images) return res.status(404).json({ error: 'Job not found' });
  res.json({ images, complete: images.every(u => u !== '') });
});

// ── POST /api/generate/paragraph-image ───────────────────────────────────────

router.post('/paragraph-image', async (req: AuthRequest, res: Response) => {
  try {
    const { paragraphText, storyContext, paragraphIndex, totalParagraphs } = req.body as {
      paragraphText: string; storyContext: string; paragraphIndex: number; totalParagraphs: number;
    };
    if (!paragraphText) return res.status(400).json({ error: 'paragraphText required' });
    const drift = totalParagraphs > 1 ? paragraphIndex / (totalParagraphs - 1) : 0;
    const imageUrl = await generateParagraphImage(paragraphText, storyContext ?? '', drift);
    res.json({ imageUrl });
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
    const imageUrl = await generateParagraphImage(prompt, '', 0.5);
    res.json({ imageUrl });
  } catch (error: any) {
    console.error('❌ Image generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate image', details: error.message });
  }
});

// ── POST /api/generate/minigame ───────────────────────────────────────────────
// Generates a MinigameTrigger for a pre-generated story paragraph.

router.post('/minigame', async (req: AuthRequest, res: Response) => {
  try {
    const { paragraphText, storyContext, childAge, paragraphIndex } = req.body as {
      paragraphText: string;
      storyContext: string;
      childAge?: number;
      paragraphIndex?: number;
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
      // Rotate fallback types by paragraph index
      const types = ['multiple_choice', 'drawing', 'voice', 'shape_sorting'] as const;
      const type  = types[pIdx % 4];
      trigger = type === 'drawing'
        ? { type: 'drawing', narratorPrompt: 'Draw what you see in the story!', drawingTheme: 'a magical scene', drawingDarkBackground: true, timeoutSeconds: 40 }
        : type === 'voice'
        ? { type: 'voice', narratorPrompt: 'Can you say it out loud?', voiceTarget: 'magic', voiceHint: 'Say "magic"!', timeoutSeconds: 20 }
        : type === 'shape_sorting'
        ? { type: 'shape_sorting', narratorPrompt: 'Put the shapes where they belong!',
            shapes: [
              { id: 's1', shape: 'circle',   color: '#FF6B6B', targetSlotId: 'slot_circle'   },
              { id: 's2', shape: 'square',   color: '#4ECDC4', targetSlotId: 'slot_square'   },
              { id: 's3', shape: 'triangle', color: '#45B7D1', targetSlotId: 'slot_triangle' },
            ], timeoutSeconds: 35 }
        : { type: 'multiple_choice', narratorPrompt: 'Quick question — what do you think?',
            choices: [
              { id: 'a', label: 'In the forest', emoji: '🌲', isCorrect: true  },
              { id: 'b', label: 'In the ocean',  emoji: '🌊', isCorrect: false },
              { id: 'c', label: 'In the sky',    emoji: '☁️', isCorrect: false },
            ], timeoutSeconds: 25 };
    }

    res.json(trigger);
  } catch (error: any) {
    console.error('❌ Minigame generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate minigame', details: error.message });
  }
});

export default router;


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

// ── Gemini 2.5 Flash image generation ────────────────────────────────────────

const GEMINI_IMAGE_MODEL = 'gemini-2.0-flash-exp-image-generation';
const GEMINI_IMAGE_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_IMAGE_MODEL}:generateContent`;

/**
 * Generate one storybook illustration using Gemini 2.5 Flash.
 * Returns a permanent local URL  (e.g. /images/abc.png) served by Express.
 */
async function generateParagraphImage(
  paragraphText: string,
  storyContext: string,
  driftPercent: number,   // 0-1: how far through the story (affects palette)
): Promise<string> {
  const apiKey = process.env.GOOGLE_API_KEY;
  if (!apiKey) throw new Error('GOOGLE_API_KEY not configured');

  // Palette shifts from warm/golden → cool/moonlit as the story progresses
  const palette =
    driftPercent < 0.33 ? 'warm golden light, soft amber tones, cozy and inviting' :
    driftPercent < 0.66 ? 'soft twilight, muted purples and blues, dreamy atmosphere' :
                          'cool moonlit night, deep indigo, gentle silver glow, tranquil';

  const prompt =
    `Children's storybook illustration. ` +
    `Overall story: ${storyContext.slice(0, 200)}. ` +
    `Current scene: ${paragraphText.slice(0, 300)}. ` +
    `Style: watercolor painting, ${palette}, soft edges, ` +
    `no text, no words, no letters, wide landscape format, 4:3 aspect ratio.`;

  const body = {
    contents: [{ parts: [{ text: prompt }] }],
    generationConfig: { responseModalities: ['IMAGE', 'TEXT'] },
  };

  const resp = await axios.post(`${GEMINI_IMAGE_URL}?key=${apiKey}`, body, {
    headers: { 'Content-Type': 'application/json' },
    timeout: 60_000,
  });

  const parts = resp.data?.candidates?.[0]?.content?.parts ?? [];
  const imgPart = parts.find((p: any) => p.inlineData);
  if (!imgPart) throw new Error('No image in Gemini response');

  const { mimeType, data: b64 } = imgPart.inlineData;
  const ext = mimeType === 'image/png' ? 'png' : mimeType === 'image/webp' ? 'webp' : 'jpg';
  const filename = `${uuid()}.${ext}`;
  fs.writeFileSync(path.join(UPLOADS_DIR, filename), Buffer.from(b64, 'base64'));

  return `/images/${filename}`;
}

/** Run an array of async tasks with limited concurrency. */
async function pMap<T, R>(
  items: T[],
  fn: (item: T, index: number) => Promise<R>,
  concurrency = 5,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let idx = 0;

  async function worker() {
    while (idx < items.length) {
      const i = idx++;
      results[i] = await fn(items[i], i);
    }
  }

  const workers = Array.from({ length: Math.min(concurrency, items.length) }, worker);
  await Promise.all(workers);
  return results;
}

// ── POST /api/generate/story ──────────────────────────────────────────────────

router.post('/story', async (req: AuthRequest, res: Response) => {
  try {
    const { profile } = req.body as { profile: ChildProfile };

    if (!profile?.name || !profile?.parentPrompt) {
      return res.status(400).json({ error: 'Invalid profile data' });
    }
    if (!process.env.ANTHROPIC_API_KEY) {
      return res.status(500).json({ error: 'Anthropic API key not configured' });
    }
    if (!process.env.GOOGLE_API_KEY) {
      return res.status(500).json({ error: 'Google API key not configured' });
    }

    const paragraphCount = paragraphCountForDuration(profile.targetDuration ?? 15);
    console.log(`📖 ${profile.name} | ${profile.targetDuration ?? 15} min | ${paragraphCount} paragraphs`);

    let childData = null;
    if (profile.childId) {
      childData = await prisma.child.findUnique({
        where: { id: profile.childId },
        include: { preferences: true },
      });
    }
    const childPersonality = childData?.preferences?.personality || '';
    const childMedia       = childData?.preferences?.favoriteMedia || '';

    // ── 1. Generate story text (Claude Sonnet) ────────────────────────────────
    const storyPrompt =
      `You are a bedtime story narrator. Create a calming, soothing bedtime story told in third person.\n\n` +
      `Theme/idea: ${profile.parentPrompt}\n` +
      `Tone: ${profile.storytellingTone}\n` +
      `Target age: ${profile.age}\n` +
      (childPersonality ? `Child's personality (tailor themes, do NOT address child): ${childPersonality}\n` : '') +
      (childMedia       ? `Child's interests (weave into plot naturally): ${childMedia}\n` : '') +
      `\nIMPORTANT RULES:\n` +
      `- Do NOT use the name "${profile.name}" in the story.\n` +
      `- Tell a story about characters, animals, or magical beings — not about the child.\n` +
      `- Third-person narration only ("the little fox walked...", "she whispered...").\n` +
      `- The story gradually slows, becomes dreamier as it progresses.\n` +
      `- Write EXACTLY ${paragraphCount} paragraphs. Each paragraph is 2-3 short sentences (~60 words).\n` +
      `- Complete arc: opening → build-up → gentle climax → slow dreamy resolution.\n\n` +
      `Format: ONLY the story paragraphs, separated by double line breaks. No titles, no "The End".`;

    const storyResp = await claude.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 8192,
      messages: [{ role: 'user', content: storyPrompt }],
    });
    const storyText = (storyResp.content[0] as { type: string; text: string }).text.trim();
    console.log(`✅ Story text generated (${storyText.length} chars)`);

    // ── 2. Generate one Gemini image per paragraph (concurrency 5) ────────────
    const paragraphs = storyText
      .split(/\n\n+/)
      .map(p => p.trim())
      .filter(Boolean);

    const storyContext = `${profile.parentPrompt} — ${profile.storytellingTone} tone`;

    console.log(`🎨 Generating ${paragraphs.length} paragraph images with Gemini…`);
    const generatedImages = await pMap(
      paragraphs,
      async (para, i) => {
        try {
          const url = await generateParagraphImage(para, storyContext, i / Math.max(1, paragraphs.length - 1));
          console.log(`  ✅ Image ${i + 1}/${paragraphs.length}: ${url}`);
          return url;
        } catch (err: any) {
          console.warn(`  ⚠️ Image ${i + 1} failed: ${err.message}`);
          return '';   // empty string — iOS falls back to gradient
        }
      },
      5,
    );
    console.log(`✅ Images done: ${generatedImages.filter(Boolean).length}/${paragraphs.length} succeeded`);

    res.json({ story: storyText, generatedImages, modelUsed: 'claude-sonnet-4-5' });

  } catch (error: any) {
    console.error('❌ Story generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate story', details: error.message });
  }
});

// ── POST /api/generate/paragraph-image ───────────────────────────────────────
// On-demand image for a single paragraph during live playback (pre-fetch ahead).

router.post('/paragraph-image', async (req: AuthRequest, res: Response) => {
  try {
    const { paragraphText, storyContext, paragraphIndex, totalParagraphs } = req.body as {
      paragraphText: string;
      storyContext: string;
      paragraphIndex: number;
      totalParagraphs: number;
    };

    if (!paragraphText) return res.status(400).json({ error: 'paragraphText required' });

    const drift = totalParagraphs > 1 ? paragraphIndex / (totalParagraphs - 1) : 0;
    const imageUrl = await generateParagraphImage(paragraphText, storyContext ?? '', drift);

    res.json({ imageUrl });
  } catch (error: any) {
    console.error('❌ Paragraph image error:', error.message);
    res.status(500).json({ error: 'Failed to generate image', details: error.message });
  }
});

// ── POST /api/generate/image (legacy — kept for compatibility) ────────────────

router.post('/image', async (req: AuthRequest, res: Response) => {
  try {
    const { prompt } = req.body;
    if (!prompt) return res.status(400).json({ error: 'Prompt is required' });

    const imageUrl = await generateParagraphImage(prompt, '', 0.5);
    res.json({ imageUrl });
  } catch (error: any) {
    console.error('❌ Image generation error:', error.message);
    res.status(500).json({ error: 'Failed to generate image', details: error.message });
  }
});

export default router;
