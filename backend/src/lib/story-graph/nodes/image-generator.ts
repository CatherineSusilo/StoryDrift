import axios from 'axios';
import fs from 'fs';
import path from 'path';
import { v4 as uuid } from 'uuid';
import Anthropic from '@anthropic-ai/sdk';
import { GoogleAuth } from 'google-auth-library';

// ── Local storage setup ────────────────────────────────────────────────────────

const UPLOADS_DIR = path.join(process.cwd(), 'uploads', 'story-images');
if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR, { recursive: true });

const claude = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const VERTEX_PROJECT  = process.env.VERTEX_AI_PROJECT  || 'hackcanada-489602';
const VERTEX_LOCATION = process.env.VERTEX_AI_LOCATION || 'us-central1';

const vertexAuth = new GoogleAuth({
  keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS || './vertex-ai-key.json',
  scopes: ['https://www.googleapis.com/auth/cloud-platform'],
});

export interface ImageResult {
  imageUrl: string;   // permanent local URL served by Express (e.g. /images/abc.png)
  falUrl:   string;   // kept for call-site compatibility — always '' with Vertex AI
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
          `Extract a single vivid image prompt from this story paragraph for a children's storybook illustration.\n\n` +
          `PARAGRAPH:\n"${segment}"\n\n` +
          `VISUAL TONE: ${visualTone}${conceptHint}\n\n` +
          `Rules:\n- One sentence only, max 40 words\n` +
          `- Describe the exact scene: specific characters, their actions, the setting\n` +
          `- Include the visual tone naturally\n` +
          `- End with: ${STYLE_SUFFIX}\n` +
          `- No quotes, no preamble, just the prompt itself`,
      }],
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

export async function generateSceneImage(
  segment: string,
  score: number,
  mode: 'bedtime' | 'educational',
  recentFalUrls: string[] = [],   // kept for call-site compat — unused with Vertex AI
  lessonConcept?: string,
): Promise<ImageResult> {
  const keyFile = process.env.GOOGLE_APPLICATION_CREDENTIALS || './vertex-ai-key.json';
  if (!fs.existsSync(keyFile)) {
    console.warn('⚠️ Vertex AI key not found — skipping image generation');
    return { imageUrl: '', falUrl: '', prompt: '' };
  }

  const imagePrompt = await buildImagePrompt(segment, score, mode, lessonConcept);
  console.log(`🎨 Image prompt: ${imagePrompt.slice(0, 80)}…`);

  try {
    const imageUrl = await generateWithVertexAI(imagePrompt);
    return { imageUrl, falUrl: '', prompt: imagePrompt };
  } catch (err: any) {
    console.error('❌ Image generation error:', err.message);
    return { imageUrl: '', falUrl: '', prompt: imagePrompt };
  }
}

// ── Vertex AI Imagen 3 ────────────────────────────────────────────────────────

async function generateWithVertexAI(prompt: string): Promise<string> {
  const client = await vertexAuth.getClient();
  const token  = await client.getAccessToken();
  if (!token.token) throw new Error('Failed to get Vertex AI access token');

  const endpoint =
    `https://${VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}` +
    `/locations/${VERTEX_LOCATION}/publishers/google/models/imagen-3.0-fast-generate-001:predict`;

  const response = await axios.post(
    endpoint,
    {
      instances:  [{ prompt }],
      parameters: { sampleCount: 1, aspectRatio: '4:3', safetyFilterLevel: 'block_some', personGeneration: 'dont_allow' },
    },
    {
      headers: { Authorization: `Bearer ${token.token}`, 'Content-Type': 'application/json' },
      timeout: 60_000,
    },
  );

  const predictions = response.data?.predictions ?? [];
  if (!predictions.length) throw new Error('No image generated from Vertex AI');

  const base64 = predictions[0].bytesBase64Encoded;
  if (!base64) throw new Error('No image data in Vertex AI response');

  const mime     = predictions[0].mimeType || 'image/png';
  const ext      = mime.includes('jpeg') ? 'jpg' : 'png';
  const filename = `${uuid()}.${ext}`;

  fs.writeFileSync(path.join(UPLOADS_DIR, filename), Buffer.from(base64, 'base64'));
  console.log(`💾 Image saved: ${filename}`);

  return `/images/${filename}`;
}
