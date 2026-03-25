import axios from 'axios';

interface ImageResult {
  imageUrl: string;
  prompt: string;
}

// Map score to visual style
function getVisualTone(score: number, mode: 'bedtime' | 'educational'): string {
  if (mode === 'bedtime') {
    if (score <= 25) return 'bright, warm, vivid colors, golden sunlight, children illustration style';
    if (score <= 50) return 'golden hour lighting, soft amber tones, warm cozy atmosphere, children book illustration';
    if (score <= 75) return 'dusk lighting, cool blues and purples, soft dreamy atmosphere, watercolor illustration style';
    return 'moonlit scene, near darkness, minimal detail, deep blues and indigos, very soft and quiet, watercolor';
  } else {
    // Educational
    if (score <= 30) return 'muted, simple, calm colors, minimal distractions, soft illustration style';
    if (score <= 60) return 'warm, clear, inviting colors, friendly scene, children book illustration';
    if (score <= 85) return 'bright, detailed, rich colors, peak learning energy, vibrant children illustration';
    return 'simplified, soft colors, reduced visual load, calm and clear, gentle illustration';
  }
}

// Extract a concise scene description from story text for the image prompt
function extractSceneDescription(segment: string): string {
  // Use first 2 sentences as the scene basis
  const sentences = segment.match(/[^.!?]+[.!?]+/g) || [segment];
  return sentences.slice(0, 2).join(' ').trim();
}

/**
 * Node 6/7 — IMAGE GENERATOR (Fal.ai + Flux)
 *
 * Generates a scene illustration that visually reflects the current
 * drift/engagement score and the story scene.
 */
export async function generateSceneImage(
  segment: string,
  score: number,
  mode: 'bedtime' | 'educational',
  referenceImageUrls?: string[],   // last 2 frames for style consistency
  lessonConcept?: string,           // highlight concept visually (educational)
): Promise<ImageResult> {
  const sceneDesc = extractSceneDescription(segment);
  const visualTone = getVisualTone(score, mode);

  let imagePrompt = `${sceneDesc}. ${visualTone}, children's storybook illustration, no text, no words, painterly style`;

  if (lessonConcept) {
    imagePrompt += `, clearly showing ${lessonConcept} in the scene`;
  }

  const apiKey = process.env.FAL_API_KEY;

  if (!apiKey) {
    console.warn('⚠️ FAL_API_KEY not configured — skipping image generation');
    return { imageUrl: '', prompt: imagePrompt };
  }

  try {
    const payload: Record<string, unknown> = {
      prompt: imagePrompt,
      image_size: 'landscape_4_3',
      num_inference_steps: 28,
      guidance_scale: 3.5,
      num_images: 1,
      enable_safety_checker: true,
    };

    // IP-Adapter style reference: pass last 2 generated frames for visual consistency
    if (referenceImageUrls && referenceImageUrls.length > 0) {
      payload.ip_adapter_image_url = referenceImageUrls[referenceImageUrls.length - 1];
      payload.ip_adapter_scale = 0.3 + (score / 100) * 0.2; // stronger reference as score rises
    }

    const response = await axios.post(
      'https://queue.fal.run/fal-ai/flux/schnell',
      payload,
      {
        headers: {
          Authorization: `Key ${apiKey}`,
          'Content-Type': 'application/json',
        },
        timeout: 30000,
      },
    );

    // Fal.ai queue — poll for result
    const requestId = response.data?.request_id;
    if (requestId) {
      return await pollFalResult(requestId, apiKey, imagePrompt);
    }

    // Direct response
    const imageUrl = response.data?.images?.[0]?.url ?? '';
    return { imageUrl, prompt: imagePrompt };
  } catch (err: any) {
    console.error('❌ Image generation error:', err.response?.data || err.message);
    return { imageUrl: '', prompt: imagePrompt };
  }
}

async function pollFalResult(
  requestId: string,
  apiKey: string,
  prompt: string,
  maxAttempts = 15,
): Promise<ImageResult> {
  for (let i = 0; i < maxAttempts; i++) {
    await new Promise((r) => setTimeout(r, 2000));
    try {
      const res = await axios.get(`https://queue.fal.run/fal-ai/flux/schnell/requests/${requestId}`, {
        headers: { Authorization: `Key ${apiKey}` },
      });
      if (res.data?.status === 'COMPLETED') {
        const imageUrl = res.data?.output?.images?.[0]?.url ?? '';
        return { imageUrl, prompt };
      }
      if (res.data?.status === 'FAILED') {
        console.error('❌ Fal.ai generation failed:', res.data);
        return { imageUrl: '', prompt };
      }
    } catch {
      // continue polling
    }
  }
  console.warn('⚠️ Fal.ai polling timed out');
  return { imageUrl: '', prompt };
}
