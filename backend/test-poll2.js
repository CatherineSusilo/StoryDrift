const https = require('https');
const fs = require('fs');
const prompt = encodeURIComponent('A moonlit forest with a small fox, watercolor style, no text, wide landscape 4:3');
const url = `https://gen.pollinations.ai/image/${prompt}?width=800&height=600&nologo=true&model=flux`;
console.log('Fetching:', url);
const file = fs.createWriteStream('/tmp/test-poll2.jpg');
https.get(url, {headers:{'User-Agent':'StoryDrift/1.0'}}, res => {
  console.log('Status:', res.statusCode, 'Content-Type:', res.headers['content-type'], 'Location:', res.headers['location']||'');
  if(res.statusCode >= 300 && res.statusCode < 400 && res.headers['location']) {
    console.log('Redirect to:', res.headers['location']);
  }
  res.pipe(file);
  file.on('finish', () => {
    file.close();
    const size = fs.statSync('/tmp/test-poll2.jpg').size;
    const buf = fs.readFileSync('/tmp/test-poll2.jpg');
    const isJpeg = buf[0]===0xFF && buf[1]===0xD8;
    const isPng = buf[0]===0x89 && buf[1]===0x50;
    console.log('Done! File size:', size, 'bytes, isJPEG:', isJpeg, 'isPNG:', isPng);
  });
}).on('error', e => console.log('Error:', e.message));
