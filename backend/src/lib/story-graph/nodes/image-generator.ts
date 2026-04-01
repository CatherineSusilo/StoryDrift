import { fal } from '@fal-ai/client';
import Anthropic from '@anthropic-ai/sdk';
import axios from 'axios';
import { uploadToR2 } from '../../r2';

let claude: Anthropic;

export interface ImageResult {
  imageUrl: string;    // permanent R2 URL
  falUrl:   string;    // ephemeral FAL CDN URL — passed as reference for next image-to-image call
  prompt:   string;
}

// ── Visual tone by score ───────────────────────────────────────────────────────

function getVisualTone(score: number, mode: 'bedtime' | 'educational'): string {
  if (mode === 'bedtime') {
    if (score <= 25) return 'bright warm sunlight, vivid golden colors, lively and cheerful';
    if (score <= 50) return 'golden hour, soft amber glow, warm cozy atmosphere';
    if (score <= 75) return 'dusk, cool blues and soft purples, dreamy and hazy';
    return 'moonlit night, near-darkness, minimal detail, deep indigo, very quiet and still';
  }
  if (score <= 30) return 'muted calm colors, simple clean composition, low distraction';
  if (score <= 60) return 'warm clear inviting light, friendly and open scene';
  if (score <= 85) return 'bright rich colors, detailed and vibrant, peak visual energy';
  return 'soft simplified colors, reduced visual complexity, gentle and calm';
}

const STYLE_SUFFIX =
  "children's storybook illustration, painterly watercolor style, " +
  'no text, no words, no letters, no UI elements, soft edges, wide aspect ratio';

// ── Claude prompt extraction ────────────────────────────────────────────────────

async function buildImagePrompt(
  segment: string,
  score: number,
  mode: 'bedtime' | 'educational',
  lessonConcept?: string,
): Promise<string> {
  const visualTone  = getVisualTone(score, mode);
  const conceptHint = lessonConcept ? ` Make sure the concept "${lessonConcept}" is clearly visible.` : '';

  try {
    const response = await claude.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 120,
      messages: [
        {
          role: 'user',
          content:
            `Extract a single vivid image prompt from this story paragraph for a children's storybook illustration.\n\n` +
            `PARAGRAPH:\n"${segment}"\n\n` +
            `VISUAL TONE: ${visualTone}${conceptHint}\n\n` +
            `Rules:\n` +
            `- One sentence only, max 40 words\n` +
            `- Describe the exact scene: specific characters, their actions, the setting, foreground objects\n` +
            `- Include the visual tone naturally (lighting, palette, atmosphere)\n` +
            `- End with: ${STYLE_SUFFIX}\n` +
            `- No quotes, no preamble, just the prompt itself`,
        },
      ],
    });

    const text = (response.content[0] as { type: string; text: string }).text.trim();
    return text.replace(/^["']|["']$/g, '');
  } catch {
    const sentences = segment.match(/[^.!?]+[.!?]+/g) || [segment];
    const base = sentences.slice(0, 2).join(' ').trim();
    let prompt = `${base} ${visualTone}, ${STYLE_SUFFIX}`;
    if (lessonConcept) prompt += `, clearly showing ${lessonConcept}`;
    return prompt;
  }
}

// ── Main export ────────────────────────────────────────────────────────────────
//
// Reference strategy:
//   Segment 1: Flux Schnell text-to-image — establishes the art style
//   Segment 2: Flux Dev image-to-image with recentFalUrls[0] (style anchor)
//   Segment 3+: Flux Dev image-to-image with recentFalUrls[1] for scene continuity
//
// recentFalUrls = [firstFalUrl, prevFalUrl] — provided by graph.ts

export async function generateSceneImage(
  segment:        string,
  score:          number,
  mode:           'bedtime' | 'educational',
  recentFalUrls?: string[],  // [firstFalUrl, prevFalUrl]
  lessonConcept?: string,
): Promise<ImageResult> {
  if (!process.env.FAL_API_KEY) {
    console.warn('⚠️ FAL_API_KEY not configured — skipping image generation');
    return { imageUrl: '', falUrl: '', prompt: '' };
  }
  fal.config({ credentials: process.env.FAL_API_KEY });
  claude = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

  const firstFalUrl = recentFalUrls?.[0];
  const prevFalUrl  = recentFalUrls?.[1];

  const imagePrompt = await buildImagePrompt(segment, score, mode, lessonConcept);
  console.log(`🎨 Image prompt: ${imagePrompt.slice(0, 80)}…`);

  try {
    let falUrl: string;

    if (!firstFalUrl) {
      // ── Segment 1: no reference → text-to-image (Flux Schnell, fastest) ─────
      falUrl = await runTextToImage(imagePrompt);
    } else if (!prevFalUrl || prevFalUrl === firstFalUrl) {
      // ── Segment 2: style anchor — re-use first image to lock in art style ───
      console.log('🎨 Using first-segment image as style anchor (img2img)');
      falUrl = await runImageToImage(imagePrompt, firstFalUrl, 0.80);
    } else {
      // ── Segment 3+: scene continuity from previous + style anchor in prompt ─
      const anchored = `${imagePrompt} The illustration must match the exact same watercolor storybook art style as the opening scene.`;
      console.log('🎨 Using previous-segment image for scene continuity (img2img)');
      falUrl = await runImageToImage(anchored, prevFalUrl, strengthForScore(score));
    }

    if (!falUrl) return { imageUrl: '', falUrl: '', prompt: imagePrompt };

    const imageUrl = await downloadAndStore(falUrl);
    return { imageUrl, falUrl, prompt: imagePrompt };
  } catch (err: any) {
    console.error('❌ Image generation error:', err.message);
    return { imageUrl: '', falUrl: '', prompt: imagePrompt };
  }
}

// ── Flux Schnell — text-to-image ───────────────────────────────────────────────

async function runTextToImage(prompt: string): Promise<string> {
  console.log('🎨 Flux Schnell text-to-image');
  const result = await fal.subscribe('fal-ai/flux/schnell', {
    input: {
      prompt,
      image_size:           'landscape_4_3',
      num_inference_steps:  4,
      num_images:           1,
      enable_safety_checker: true,
      output_format:        'jpeg',
    },
  });
  return (result.data as any).images?.[0]?.url ?? '';
}

// ── Flux Dev — image-to-image ─────────────────────────────────────────────────

function strengthForScore(score: number): number {
  return Math.min(0.88, 0.75 + (score / 100) * 0.13);
}

async function runImageToImage(prompt: string, referenceUrl: string, strength: number): Promise<string> {
  console.log(`🎨 Flux Dev image-to-image (strength ${strength.toFixed(2)}, ref: ${referenceUrl.slice(0, 60)}…)`);
  const result = await fal.subscribe('fal-ai/flux/dev/image-to-image', {
    input: {
      prompt,
      image_url:            referenceUrl,
      strength,
      num_inference_steps:  28,
      guidance_scale:       3.5,
      num_images:           1,
      enable_safety_checker: true,
      output_format:        'jpeg',
    },
  });
  return (result.data as any).images?.[0]?.url ?? '';
}

// ── R2 storage ────────────────────────────────────────────────────────────────

async function downloadAndStore(falUrl: string): Promise<string> {
  try {
    const isJpeg = !falUrl.includes('.png');
    const [ext, contentType] = isJpeg ? ['jpg', 'image/jpeg'] : ['png', 'image/png'];

    const response = await axios.get(falUrl, { responseType: 'arraybuffer', timeout: 20000 });
    const r2Url = await uploadToR2(Buffer.from(response.data), ext, contentType);
    console.log(`☁️  Image uploaded to R2: ${r2Url}`);
    return r2Url;
  } catch (err: any) {
    console.error('⚠️ Image upload to R2 failed, using FAL CDN URL:', err.message);
    return falUrl;  // ephemeral fallback — valid for ~1h
  }
}
