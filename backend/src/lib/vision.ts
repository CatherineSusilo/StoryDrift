import Anthropic from '@anthropic-ai/sdk';

const claude = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

/**
 * Send a base64-encoded image to Claude and get back a detailed visual description
 * suitable for passing to image generation prompts.
 *
 * @param base64Image  Raw base64 string (no data-URL prefix)
 * @param mediaType    MIME type of the image
 * @param context      What this image represents (e.g. "a story character", "a scene theme")
 */
export async function analyseImageWithClaude(
  base64Image: string,
  mediaType: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif',
  context: string,
): Promise<string> {
  const response = await claude.messages.create({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 300,
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'image',
            source: { type: 'base64', media_type: mediaType, data: base64Image },
          },
          {
            type: 'text',
            text:
              `This image represents ${context}.\n\n` +
              `Write a comprehensive visual description that could be used in an AI image generation prompt.\n` +
              `Focus on: colors, shapes, textures, mood, style, and any notable visual features.\n` +
              `Be specific and detailed (3-5 sentences). Do not include any commentary — just the description.`,
          },
        ],
      },
    ],
  });

  return (response.content[0] as { type: string; text: string }).text.trim();
}

/**
 * Detect the MIME type of a base64 image from its first bytes.
 */
export function detectMimeType(base64: string): 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif' {
  const header = base64.slice(0, 8);
  if (header.startsWith('/9j/') || header.startsWith('iVBOR'))  return header.startsWith('/9j/') ? 'image/jpeg' : 'image/png';
  if (header.startsWith('R0lGOD')) return 'image/gif';
  if (header.startsWith('UklGRi')) return 'image/webp';
  // Default to jpeg for unknown formats
  return 'image/jpeg';
}
