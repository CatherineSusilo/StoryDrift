import axios from 'axios';
import fs from 'fs';
import path from 'path';
import { v4 as uuid } from 'uuid';

// ── Local storage setup ────────────────────────────────────────────────────────

const UPLOADS_DIR = path.join(process.cwd(), 'uploads', 'story-images');

// Ensure directory exists at import time
if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

interface ImageResult {
  imageUrl: string;      // permanent local URL  — e.g. /images/abc123.webp
  falUrl: string;        // temporary Fal.ai CDN URL — valid ~1h, use for next image-to-image
  prompt: string;
}

// ── Visual tone by score ───────────────────────────────────────────────────────

function getVisualTone(score: number, mode: 'bedtime' | 'educational'): string {
  if (mode === 'bedtime') {
    if (score <= 25) return 'bright warm sunlight, vivid golden colors, lively and cheerful';
    if (score <= 50) return 'golden hour, soft amber glow, warm cozy atmosphere';
    if (score <= 75) return 'dusk, cool blues and soft purples, dreamy and hazy';
    return 'moonlit night, near-darkness, minimal detail, deep indigo, very quiet and still';
  }
  // Educational
  if (score <= 30) return 'muted calm colors, simple clean composition, low distraction';
  if (score <= 60) return 'warm clear inviting light, friendly and open scene';
  if (score <= 85) return 'bright rich colors, detailed and vibrant, peak visual energy';
  return 'soft simplified colors, reduced visual complexity, gentle and calm';
}

// Consistent style suffix applied to every prompt — maintains visual cohesion across segments
const STYLE_SUFFIX =
  "children's storybook illustration, painterly watercolor style, " +
  'no text, no words, no letters, no UI elements, soft edges';

function extractSceneDescription(segment: string): string {
  const sentences = segment.match(/[^.!?]+[.!?]+/g) || [segment];
  return sentences.slice(0, 2).join(' ').trim();
}

// ── Main export ────────────────────────────────────────────────────────────────

/**
 * Node 6/7 — IMAGE GENERATOR (Fal.ai + Flux)
 *
 * First segment: fal-ai/flux/schnell (text-to-image, fastest)
 * Subsequent segments: fal-ai/flux/dev/image-to-image with the previous
 *   Fal.ai CDN URL as reference (strength 0.82 — mostly new scene, same art style)
 *
 * Generated images are immediately downloaded and stored permanently under
 * uploads/story-images/. The local URL is what goes into session state and
 * the iOS app — it never expires.
 */
export async function generateSceneImage(
  segment: string,
  score: number,
  mode: 'bedtime' | 'educational',
  recentFalUrls: string[] = [],    // Fal.ai CDN URLs from last 2 segments (still fresh)
  lessonConcept?: string,
): Promise<ImageResult> {
  const sceneDesc  = extractSceneDescription(segment);
  const visualTone = getVisualTone(score, mode);

  let imagePrompt = `${sceneDesc} ${visualTone}, ${STYLE_SUFFIX}`;
  if (lessonConcept) imagePrompt += `, clearly showing ${lessonConcept}`;

  const apiKey = process.env.FAL_API_KEY;
  if (!apiKey) {
    console.warn('⚠️ FAL_API_KEY not configured — skipping image generation');
    return { imageUrl: '', falUrl: '', prompt: imagePrompt };
  }

  // Pick the most recent valid Fal.ai CDN URL for image-to-image reference
  const refUrl = recentFalUrls.at(-1);

  try {
    const falUrl = refUrl
      ? await generateImageToImage(imagePrompt, refUrl, score, apiKey)
      : await generateTextToImage(imagePrompt, apiKey);

    if (!falUrl) return { imageUrl: '', falUrl: '', prompt: imagePrompt };

    // Download and store permanently
    const imageUrl = await downloadAndStore(falUrl);
    return { imageUrl, falUrl, prompt: imagePrompt };
  } catch (err: any) {
    console.error('❌ Image generation error:', err.response?.data || err.message);
    return { imageUrl: '', falUrl: '', prompt: imagePrompt };
  }
}

// ── fal-ai/flux/schnell — text-to-image (no reference) ────────────────────────

async function generateTextToImage(prompt: string, apiKey: string): Promise<string> {
  console.log('🎨 Flux Schnell text-to-image');
  const response = await axios.post(
    'https://queue.fal.run/fal-ai/flux/schnell',
    {
      prompt,
      image_size: 'landscape_4_3',
      num_inference_steps: 4,      // schnell is optimised for 4 steps
      num_images: 1,
      enable_safety_checker: true,
    },
    {
      headers: { Authorization: `Key ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 30000,
    },
  );

  const requestId = response.data?.request_id;
  if (requestId) return pollFalResult('flux/schnell', requestId, apiKey);

  return response.data?.images?.[0]?.url ?? '';
}

// ── fal-ai/flux/dev/image-to-image — style reference ─────────────────────────
//
// Why this instead of IP-Adapter:
//   Flux Schnell does NOT support IP-Adapter — those parameters are silently
//   ignored.  fal-ai/flux/dev/image-to-image accepts an image_url and a
//   strength (0–1).  At strength 0.82 the model keeps the style, palette, and
//   general character look from the previous frame while generating a fresh scene.

async function generateImageToImage(
  prompt: string,
  referenceUrl: string,
  score: number,
  apiKey: string,
): Promise<string> {
  // Strength: how much to deviate from reference.
  // Rising drift (bedtime) → weaker deviation = more visual consistency
  // Active educational → more creative freedom
  const strength = Math.min(0.95, 0.75 + score / 100 * 0.2);

  console.log(`🎨 Flux Dev image-to-image (strength ${strength.toFixed(2)}, ref: ${referenceUrl.slice(0, 50)}...)`);

  const response = await axios.post(
    'https://queue.fal.run/fal-ai/flux/dev/image-to-image',
    {
      prompt,
      image_url: referenceUrl,
      strength,
      num_inference_steps: 28,
      guidance_scale: 3.5,
      num_images: 1,
      enable_safety_checker: true,
    },
    {
      headers: { Authorization: `Key ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 45000,
    },
  );

  const requestId = response.data?.request_id;
  if (requestId) return pollFalResult('flux/dev/image-to-image', requestId, apiKey);

  return response.data?.images?.[0]?.url ?? '';
}

// ── Fal.ai queue polling ───────────────────────────────────────────────────────

async function pollFalResult(
  model: string,
  requestId: string,
  apiKey: string,
  maxAttempts = 20,
): Promise<string> {
  for (let i = 0; i < maxAttempts; i++) {
    await new Promise((r) => setTimeout(r, 2000));
    try {
      const res = await axios.get(
        `https://queue.fal.run/fal-ai/${model}/requests/${requestId}`,
        { headers: { Authorization: `Key ${apiKey}` } },
      );

      const status = res.data?.status;
      if (status === 'COMPLETED') {
        return res.data?.output?.images?.[0]?.url
          ?? res.data?.images?.[0]?.url
          ?? '';
      }
      if (status === 'FAILED') {
        console.error('❌ Fal.ai request failed:', res.data);
        return '';
      }
    } catch {
      // transient polling error — continue
    }
  }
  console.warn('⚠️ Fal.ai polling timed out');
  return '';
}

// ── Local storage ─────────────────────────────────────────────────────────────
//
// Downloads the Fal.ai CDN image immediately and saves it under
// uploads/story-images/{uuid}.webp
//
// Returns the local path that Express will serve at /images/{uuid}.webp
// This URL never expires — it's permanent as long as the server storage exists.

async function downloadAndStore(falUrl: string): Promise<string> {
  try {
    const ext = falUrl.includes('.png') ? 'png' : 'webp';
    const filename = `${uuid()}.${ext}`;
    const filePath = path.join(UPLOADS_DIR, filename);

    const response = await axios.get(falUrl, {
      responseType: 'arraybuffer',
      timeout: 20000,
    });

    fs.writeFileSync(filePath, response.data);
    console.log(`💾 Image stored: ${filename}`);

    // Return the local URL path (Express serves /images/*)
    return `/images/${filename}`;
  } catch (err: any) {
    console.error('⚠️ Image download/store failed:', err.message);
    // Fall back to Fal.ai URL — will work for ~1 hour
    return falUrl;
  }
}
