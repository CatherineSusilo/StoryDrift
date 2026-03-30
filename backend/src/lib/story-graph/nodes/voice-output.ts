import axios from 'axios';

interface VoiceParams {
  stability: number;
  similarity_boost: number;
  style: number;
  use_speaker_boost: boolean;
}

interface VoiceResult {
  audioBase64: string;
  contentType: string;
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
 */
export async function generateVoice(
  text: string,
  score: number,
  mode: 'bedtime' | 'educational',
): Promise<VoiceResult | null> {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  const voiceId = process.env.ELEVENLABS_VOICE_ID || 'EXAVITQu4vr4xnSDxMaL'; // default: Bella

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

    const audioBase64 = Buffer.from(response.data).toString('base64');
    return { audioBase64, contentType: 'audio/mpeg' };
  } catch (err: any) {
    console.error('❌ ElevenLabs voice error:', err.response?.data || err.message);
    return null;
  }
}
