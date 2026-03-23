import { Router, Response } from 'express';
import { AuthRequest } from '../middleware/auth';
import axios from 'axios';

const router = Router();

// Generate audio from text using ElevenLabs
router.post('/', async (req: AuthRequest, res: Response) => {
  try {
    const { text, voiceId = 'pNInz6obpgDQGcFmaJgB' } = req.body; // Default: Adam voice

    if (!text) {
      return res.status(400).json({ error: 'Text is required' });
    }

    if (!process.env.ELEVENLABS_API_KEY) {
      return res.status(500).json({ error: 'ElevenLabs API key not configured' });
    }

    console.log('🎙️ Generating audio with ElevenLabs...');
    console.log('   Voice ID:', voiceId);
    console.log('   Text length:', text.length);

    // Call ElevenLabs API
    const response = await axios.post(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
      {
        text,
        model_id: 'eleven_flash_v2_5',
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
        },
      },
      {
        headers: {
          'Accept': 'audio/mpeg',
          'xi-api-key': process.env.ELEVENLABS_API_KEY,
          'Content-Type': 'application/json',
        },
        responseType: 'arraybuffer',
      }
    );

    console.log('✅ Audio generated successfully');

    // Return audio file
    res.set({
      'Content-Type': 'audio/mpeg',
      'Content-Length': response.data.length,
    });
    res.send(Buffer.from(response.data));

  } catch (error: any) {
    let errorDetails = error.message;
    if (error.response?.data) {
      errorDetails = Buffer.isBuffer(error.response.data)
        ? error.response.data.toString('utf-8')
        : JSON.stringify(error.response.data);
    }
    console.error('❌ ElevenLabs API error:', errorDetails);
    res.status(500).json({ 
      error: 'Failed to generate audio',
      details: errorDetails,
    });
  }
});

// Get available voices
router.get('/voices', async (req: AuthRequest, res: Response) => {
  try {
    if (!process.env.ELEVENLABS_API_KEY) {
      return res.status(500).json({ error: 'ElevenLabs API key not configured' });
    }

    const response = await axios.get(
      'https://api.elevenlabs.io/v1/voices',
      {
        headers: {
          'xi-api-key': process.env.ELEVENLABS_API_KEY,
        },
      }
    );

    res.json(response.data);
  } catch (error: any) {
    console.error('❌ Failed to fetch voices:', error.response?.data || error.message);
    res.status(500).json({ 
      error: 'Failed to fetch voices',
      details: error.response?.data || error.message 
    });
  }
});

// Clone voice (for parent voice upload)
router.post('/clone-voice', async (req: AuthRequest, res: Response) => {
  try {
    const { name, description, files } = req.body; // files should be base64 audio data

    if (!process.env.ELEVENLABS_API_KEY) {
      return res.status(500).json({ error: 'ElevenLabs API key not configured' });
    }

    if (!name || !files || files.length === 0) {
      return res.status(400).json({ error: 'Name and audio files are required' });
    }

    console.log('🎤 Cloning voice:', name);

    const response = await axios.post(
      'https://api.elevenlabs.io/v1/voices/add',
      {
        name,
        description: description || 'Parent voice clone',
        files,
      },
      {
        headers: {
          'xi-api-key': process.env.ELEVENLABS_API_KEY,
          'Content-Type': 'application/json',
        },
      }
    );

    console.log('✅ Voice cloned successfully:', response.data.voice_id);
    res.json(response.data);

  } catch (error: any) {
    console.error('❌ Voice cloning failed:', error.response?.data || error.message);
    res.status(500).json({ 
      error: 'Failed to clone voice',
      details: error.response?.data || error.message 
    });
  }
});

export default router;
