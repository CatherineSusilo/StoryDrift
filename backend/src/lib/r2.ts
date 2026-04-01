import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { v4 as uuid } from 'uuid';

const r2 = new S3Client({
  region: 'auto',
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID!,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
  },
});

/**
 * Upload a Buffer to Cloudflare R2 and return a permanent public URL.
 * @param buffer    File content
 * @param extension File extension without dot: "webp", "png", "jpg", "mp3"
 * @param contentType MIME type: "image/webp", "image/png", "audio/mpeg"
 */
export async function uploadToR2(
  buffer: Buffer,
  extension: string,
  contentType: string,
): Promise<string> {
  const key = `${uuid()}.${extension}`;

  await r2.send(new PutObjectCommand({
    Bucket: process.env.R2_BUCKET!,
    Key: key,
    Body: buffer,
    ContentType: contentType,
  }));

  return `${(process.env.R2_PUBLIC_URL ?? '').replace(/\/$/, '')}/${key}`;
}

/**
 * Delete a file from R2 by its public URL.
 */
export async function deleteFromR2(publicUrl: string): Promise<void> {
  const key = publicUrl.split('/').pop()!;
  await r2.send(new DeleteObjectCommand({
    Bucket: process.env.R2_BUCKET!,
    Key: key,
  }));
}
