import axios from 'axios';
import { fal } from '@fal-ai/client';
import { uploadToR2 } from '../../r2';
import Anthropic from '@anthropic-ai/sdk';

// ── Local storage setup ────────────────────────────────────────────────────────

const claude = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// Configure fal — credentials already set in process.env by the time this module loads
fal.config({ credentials: process.env.FAL_API_KEY ?? '' });

export interface ImageResult {
  imageUrl: string;   // permanent R2 CDN URL
  falUrl:   string;   // ephemeral fal.ai CDN URL (for img2img reference chain)
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

// ── Claude prompt builder ─────────────────────────────────────────────────────

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
      messages: [{
        role: 'user',
        content:
          `Write a single image generation prompt (max 60 words) for a children's storybook illustration.\n` +
          `Story segment: "${segment.slice(0, 200)}"\n` +
          `Visual tone: ${visualTone}${conceptHint}\n` +
          `Style: ${STYLE_SUFFIX}\n` +
          `Output ONLY the prompt text, nothing else.`,
      }],
    });
    const text = (response.content[0] as { type: string; text: string }).text.trim();
    return text || fallbackPrompt(segment, visualTone);
  } catch {
    return fallbackPrompt(segment, visualTone);
  }
}

function fallbackPrompt(segment: string, visualTone: string): string {
  const sentences = segment.split(/[.!?]/).filter(Boolean);
  const base = sentences.slice(0, 2).join(' ').trim();
  return `${base} ${visualTone}, ${STYLE_SUFFIX}`;
}

// ── fal.ai image generation ───────────────────────────────────────────────────

async function generateWithFal(
  prompt: string,
  prevFalUrl?: string,   // reference image for img2img continuity
): Promise<{ imageUrl: string; falUrl: string }> {
  if (!process.env.FAL_API_KEY) throw new Error('FAL_API_KEY not configured');

  let falUrl: string;

  if (prevFalUrl) {
    // img2img — maintain visual continuity with previous scene
    const result = await fal.subscribe('fal-ai/flux/dev/image-to-image', {
      input: {
        prompt,
        image_url:             prevFalUrl,
        strength:              0.78,
        num_inference_steps:   28,
        guidance_scale:        3.5,
        num_images:            1,
        enable_safety_checker: true,
        output_format:         'jpeg',
      },
    });
    falUrl = (result.data as any).images?.[0]?.url ?? '';
  } else {
    // text-to-image for first segment
    const result = await fal.subscribe('fal-ai/flux/schnell', {
      input: {
        prompt,
        image_size:            'landscape_4_3',
        num_inference_steps:   4,
        num_images:            1,
        enable_safety_checker: true,
        output_format:         'jpeg',
      },
    });
    falUrl = (result.data as any).images?.[0]?.url ?? '';
  }

  if (!falUrl) throw new Error('No image URL returned from fal.ai');

  // Download from fal CDN and upload to R2 for permanent storage
  const resp = await axios.get(falUrl, { responseType: 'arraybuffer', timeout: 20000 });
  const contentType = ((resp.headers['content-type'] as string) || 'image/jpeg').split(';')[0].trim();
  const ext = contentType.includes('png') ? 'png' : 'jpg';
  const imageUrl = await uploadToR2(Buffer.from(resp.data), ext, contentType);

  return { imageUrl, falUrl };
}

// ── Main export ────────────────────────────────────────────────────────────────

export async function generateSceneImage(
  segment: string,
  score: number,
  mode: 'bedtime' | 'educational',
  recentFalUrls: string[] = [],   // previous fal URLs for img2img continuity
  lessonConcept?: string,
): Promise<ImageResult> {
  try {
    const prompt    = await buildImagePrompt(segment, score, mode, lessonConcept);
    console.log(`🎨 Image prompt: ${prompt.slice(0, 80)}…`);

    // Use the most recent fal URL as img2img reference if available
    const prevFalUrl = recentFalUrls.length > 0 ? recentFalUrls[recentFalUrls.length - 1] : undefined;
    const { imageUrl, falUrl } = await generateWithFal(prompt, prevFalUrl);

    console.log(`✅ Image uploaded to R2: ${imageUrl}`);
    return { imageUrl, falUrl, prompt };
  } catch (err: any) {
    console.error('❌ Image generation error:', err.message);
    return { imageUrl: '', falUrl: '', prompt: '' };
  }
}
