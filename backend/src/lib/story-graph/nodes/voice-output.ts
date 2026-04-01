import axios from 'axios';
import { uploadToR2 } from '../../r2';

interface VoiceParams {
  stability: number;
  similarity_boost: number;
  style: number;
  use_speaker_boost: boolean;
}

interface VoiceResult {
  audioUrl: string;   // permanent R2 CDN URL
}

// Map drift/engagement score to ElevenLabs voice parameters
function getBedtimeVoiceParams(driftScore: number): { params: VoiceParams; speed: number } {
  const t = driftScore / 100;
  return {
    params: {
      stability:        0.75 + t * 0.20,  // very stable, consistent lull
      similarity_boost: 0.80,
      style:            Math.max(0, 0.25 - t * 0.25), // near-flat delivery as child nears sleep
      use_speaker_boost: false,            // keep volume gentle
    },
    speed: 0.75 - t * 0.20,              // 0.75 → 0.55 — always slow, gets slower
  };
}

function getEducationalVoiceParams(engagementScore: number): { params: VoiceParams; speed: number } {
  if (engagementScore <= 30) {
    // Bored — more energetic, questioning tone
    return {
      params: { stability: 0.5, similarity_boost: 0.8, style: 0.6, use_speaker_boost: true },
      speed: 1.1,
    };
  } else if (engagementScore <= 85) {
    // Optimal window — slightly slower, emphasise concept
    return {
      params: { stability: 0.65, similarity_boost: 0.8, style: 0.4, use_speaker_boost: true },
      speed: 0.95,
    };
  } else {
    // Overstimulated — calm down
    return {
      params: { stability: 0.75, similarity_boost: 0.8, style: 0.2, use_speaker_boost: true },
      speed: 0.85,
    };
  }
}

/**
 * Node 7/8 — ELEVENLABS VOICE OUTPUT
 *
 * Generates narration audio for the story segment, with voice parameters
 * adapted to the current drift or engagement score.
 *
 * @param voiceIdOverride  Optional ElevenLabs voice ID (e.g. child's saved narrator voice).
 *                         Falls back to ELEVENLABS_VOICE_ID env var, then 'EXAVITQu4vr4xnSDxMaL' (Bella).
 */
export async function generateVoice(
  text: string,
  score: number,
  mode: 'bedtime' | 'educational',
  voiceIdOverride?: string,
): Promise<VoiceResult | null> {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  const voiceId = voiceIdOverride || process.env.ELEVENLABS_VOICE_ID || 'EXAVITQu4vr4xnSDxMaL'; // default: Bella

  if (!apiKey) {
    console.warn('⚠️ ELEVENLABS_API_KEY not configured — skipping voice generation');
    return null;
  }

  const { params, speed } =
    mode === 'bedtime'
      ? getBedtimeVoiceParams(score)
      : getEducationalVoiceParams(score);

  try {
    const response = await axios.post(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
      {
        text,
        model_id: 'eleven_turbo_v2_5',   // best prosody for narration
        voice_settings: params,
        speed,                            // top-level — controls overall pace
      },
      {
        headers: {
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
          Accept: 'audio/mpeg',
        },
        responseType: 'arraybuffer',
        timeout: 30000,
      },
    );

    const audioUrl = await uploadToR2(Buffer.from(response.data), 'mp3', 'audio/mpeg');
    console.log(`✅ Audio uploaded to R2: ${audioUrl}`);
    return { audioUrl };
  } catch (err: any) {
    console.error('❌ ElevenLabs voice error:', err.response?.data || err.message);
    return null;
  }
}
