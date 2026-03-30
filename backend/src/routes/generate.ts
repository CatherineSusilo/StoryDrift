import { Router, Response } from 'express';
import { AuthRequest } from '../middleware/auth';
import { prisma } from '../lib/prisma';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
import { v4 as uuid } from 'uuid';
import Anthropic from '@anthropic-ai/sdk';
import { GoogleAuth } from 'google-auth-library';

const router = Router();
const claude = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const UPLOADS_DIR = path.join(process.cwd(), 'uploads', 'story-images');
if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR, { recursive: true });

// Google Auth for Vertex AI REST API
const auth = new GoogleAuth({
  keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS || './vertex-ai-key.json',
  scopes: ['https://www.googleapis.com/auth/cloud-platform'],
});

const VERTEX_PROJECT = process.env.VERTEX_AI_PROJECT || 'hackcanada-489602';
const VERTEX_LOCATION = process.env.VERTEX_AI_LOCATION || 'us-central1';

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

// ── Vertex AI Imagen via REST API ───────────────────────────────────────────

const delay = (ms: number) => new Promise(r => setTimeout(r, ms));

/**
 * Generate storybook illustration using Vertex AI Imagen via REST API.
 * Uses service account authentication for proper quota.
 */
async function generateParagraphImage(
  paragraphText: string,
  storyContext: string,
  driftPercent: number,
): Promise<string> {
  try {
    const palette =
      driftPercent < 0.33 ? 'warm golden light, soft amber tones, cozy' :
      driftPercent < 0.66 ? 'soft twilight, muted purples and blues, dreamy' :
                            'cool moonlit night, deep indigo, silver glow, tranquil';

    const prompt =
      `Children's bedtime storybook illustration. ` +
      `Story: ${storyContext.slice(0, 150)}. Scene: ${paragraphText.slice(0, 250)}. ` +
      `Watercolor style, ${palette}, soft edges, no text, 4:3 landscape, dreamy calming atmosphere.`;

    // Get access token from service account
    const client = await auth.getClient();
    const accessToken = await client.getAccessToken();
    
    if (!accessToken.token) throw new Error('Failed to get access token');

    // Call Vertex AI Imagen 3 predict API with current model version
    const endpoint = `https://${VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}/locations/${VERTEX_LOCATION}/publishers/google/models/imagen-3.0-fast-generate-001:predict`;
    
    const response = await axios.post(endpoint, {
      instances: [{ prompt }],
      parameters: {
        sampleCount: 1,
        aspectRatio: '4:3',
        safetyFilterLevel: 'block_some',
        personGeneration: 'dont_allow',
      },
    }, {
      headers: {
        'Authorization': `Bearer ${accessToken.token}`,
        'Content-Type': 'application/json',
      },
      timeout: 60_000,
    });

    const predictions = response.data?.predictions || [];
    if (predictions.length === 0) throw new Error('No image generated');

    const base64Data = predictions[0].bytesBase64Encoded;
    if (!base64Data) throw new Error('No image data in response');

    const mimeType = predictions[0].mimeType || 'image/png';
    const ext = mimeType.includes('jpeg') ? 'jpg' : 'png';
    const filename = `${uuid()}.${ext}`;
    
    const buffer = Buffer.from(base64Data, 'base64');
    fs.writeFileSync(path.join(UPLOADS_DIR, filename), buffer);
    
    return `/images/${filename}`;
  } catch (err: any) {
    console.error('⚠️ Vertex AI image error:', err.message);
    if (err.response?.data) console.error('Response:', JSON.stringify(err.response.data).slice(0, 300));
    throw err;
  }
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

    // ── Phase 3: Vertex AI Imagen 3 — background generation ───────────────────
    const tempStoryId = uuid();
    const pending = new Array(paragraphs.length).fill('');
    imageProgress.set(tempStoryId, pending);

    console.log(`🎨 Starting Vertex AI image generation for ${tempStoryId}…`);
    (async () => {
      for (let i = 0; i < paragraphs.length; i++) {
        if (i > 0) await delay(2_000); // 2s between requests
        try {
          const url = await generateParagraphImage(paragraphs[i], storyContext, i / total);
          pending[i] = url;
          console.log(`  🖼  Image ${i + 1}/${paragraphs.length}: ${url}`);
        } catch (err: any) {
          console.warn(`  ⚠️  Image ${i + 1} failed: ${err.message}`);
        }
      }
      console.log(`✅ All images done for ${tempStoryId}`);
      setTimeout(() => imageProgress.delete(tempStoryId), 60 * 60 * 1000);
    })();

    res.json({
      story: storyText,
      generatedImages: [],
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
