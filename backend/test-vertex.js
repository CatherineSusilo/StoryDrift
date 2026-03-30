// Test Vertex AI Imagen 3 image generation
import { VertexAI } from '@google-cloud/vertexai';

const vertexAI = new VertexAI({
  project: 'hackcanada-489602',
  location: 'us-central1',
});

async function testImageGen() {
  try {
    console.log('🎨 Testing Vertex AI Imagen 3...');
    
    const generativeModel = vertexAI.preview.getGenerativeModel({
      model: 'imagen-3.0-generate-001',
      generationConfig: {
        numberOfImages: 1,
        aspectRatio: '4:3',
        personGeneration: 'dont_allow',
        safetySetting: 'block_some',
      },
    });

    const prompt = 'A moonlit forest with a small fox sleeping under a tree. Watercolor style, soft colors, no text, dreamy bedtime illustration.';
    
    const result = await generativeModel.generateContent({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
    });

    const candidates = result.response?.candidates || [];
    console.log('✅ Got', candidates.length, 'candidates');
    
    if (candidates.length > 0) {
      const parts = candidates[0].content?.parts || [];
      const imgPart = parts.find((p: any) => p.inlineData);
      if (imgPart && imgPart.inlineData?.data) {
        const base64 = imgPart.inlineData.data;
        console.log('✅ Image data length:', base64.length, 'bytes');
        console.log('✅ Mime type:', imgPart.inlineData.mimeType);
        
        // Save to file
        const fs = require('fs');
        const buffer = Buffer.from(base64, 'base64');
        fs.writeFileSync('/tmp/test-vertex.png', buffer);
        console.log('✅ Saved to /tmp/test-vertex.png');
      } else {
        console.log('❌ No image data in response');
      }
    }
  } catch (err) {
    console.error('❌ Error:', err.message);
    if (err.response?.data) console.error('Response:', JSON.stringify(err.response.data).slice(0, 500));
  }
}

testImageGen();
