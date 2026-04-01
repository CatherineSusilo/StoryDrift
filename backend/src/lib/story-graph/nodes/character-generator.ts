import Anthropic from '@anthropic-ai/sdk';
import { fal } from '@fal-ai/client';
import axios from 'axios';
import { uploadToR2 } from '../../r2';

const claude = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

export interface GeneratedCharacter {
  name: string;
  description: string;
  temperament: string;
  imageUrl: string;     // permanent R2 URL
  falImageUrl: string;  // ephemeral fal.ai CDN URL for img2img pipeline
}

/**
 * Use Claude Haiku to infer a character's physical description and temperament
 * from their name and the surrounding story context.
 */
export async function generateCharacterProfile(
  name: string,
  storyContext: string,
  childAge: number,
): Promise<{ description: string; temperament: string }> {
  try {
    const response = await claude.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 200,
      messages: [{
        role: 'user',
        content:
          `A character named "${name}" just appeared in a children's story for a ${childAge}-year-old.\n` +
          `Story context: "${storyContext.slice(0, 300)}"\n\n` +
          `Create a brief, imaginative character profile consistent with the story context.\n` +
          `Return ONLY valid JSON, no markdown:\n` +
          `{"description": "physical appearance in 1-2 sentences", "temperament": "personality traits in 1-2 sentences"}`,
      }],
    });

    const text = (response.content[0] as { type: string; text: string }).text;
    const cleaned = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
    const parsed = JSON.parse(cleaned);
    return {
      description: parsed.description ?? `A friendly character named ${name}.`,
      temperament: parsed.temperament ?? `Curious and kind-hearted.`,
    };
  } catch {
    return {
      description: `A friendly character named ${name}.`,
      temperament: `Curious and kind-hearted.`,
    };
  }
}

/**
 * Generate a reference portrait for a character using Flux Schnell (text-to-image).
 * The resulting fal.ai CDN URL is stored alongside the permanent R2 URL so it can
 * be passed as an img2img reference in subsequent scene images to keep the
 * character visually consistent throughout the session.
 */
export async function generateCharacterReferenceImage(
  name: string,
  description: string,
  temperament: string,
): Promise<{ imageUrl: string; falImageUrl: string }> {
  if (!process.env.FAL_API_KEY) {
    console.warn('⚠️ FAL_API_KEY not set — skipping character image generation');
    return { imageUrl: '', falImageUrl: '' };
  }

  fal.config({ credentials: process.env.FAL_API_KEY });

  const prompt =
    `Children's storybook character portrait of ${name}. ${description} ` +
    `Personality: ${temperament} ` +
    `Painterly watercolor style, soft warm colors, expressive and friendly face, ` +
    `white or light background, no text, no words, square format, high quality.`;

  try {
    const result = await fal.subscribe('fal-ai/flux/schnell', {
      input: {
        prompt,
        image_size:            'square',
        num_inference_steps:   4,
        num_images:            1,
        enable_safety_checker: true,
        output_format:         'jpeg',
      },
    });

    const falImageUrl = (result.data as any).images?.[0]?.url ?? '';
    if (!falImageUrl) return { imageUrl: '', falImageUrl: '' };

    const resp = await axios.get(falImageUrl, { responseType: 'arraybuffer', timeout: 20000 });
    const imageUrl = await uploadToR2(Buffer.from(resp.data), 'jpg', 'image/jpeg');
    console.log(`🎭 Character reference image stored: ${imageUrl}`);

    return { imageUrl, falImageUrl };
  } catch (err: any) {
    console.error(`❌ Character image generation failed for "${name}":`, err.message);
    return { imageUrl: '', falImageUrl: '' };
  }
}
