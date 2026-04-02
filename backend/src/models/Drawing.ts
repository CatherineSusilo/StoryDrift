import { Schema, model, Document, Types } from 'mongoose';

export interface IDrawing extends Document {
  userId: Types.ObjectId;
  childId: Types.ObjectId;
  name: string;
  imageUrl: string;       // R2 cloud storage URL
  imageData?: Buffer;     // Legacy: PNG image stored as binary (deprecated, kept for backwards compatibility)
  uploadedAt: Date;
  source: 'manual_upload' | 'minigame';  // Track where drawing came from
  lessonName?: string;    // If from minigame, which lesson
  lessonEmoji?: string;   // Emoji for the lesson
  createdAt: Date;
  updatedAt: Date;
}

const DrawingSchema = new Schema<IDrawing>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    childId: { type: Schema.Types.ObjectId, ref: 'Child', required: true, index: true },
    name: { type: String, required: true },
    imageUrl: { type: String },          // R2 cloud storage URL (required for new drawings)
    imageData: { type: Buffer },         // Legacy binary blob (deprecated)
    uploadedAt: { type: Date, required: true },
    source: { type: String, enum: ['manual_upload', 'minigame'], default: 'manual_upload' },
    lessonName: { type: String },
    lessonEmoji: { type: String },
  },
  {
    timestamps: true,
    toJSON: {
      transform: (_doc, ret: any) => {
        ret.id = ret._id.toString();
        ret.childId = ret.childId?.toString();
        ret.userId = ret.userId?.toString();
        
        // For backwards compatibility: convert binary buffer to base64 if imageUrl not present
        if (!ret.imageUrl && ret.imageData) {
          ret.imageData = ret.imageData.toString('base64');
        } else if (ret.imageUrl) {
          // If we have imageUrl, remove imageData from response
          ret.imageData = undefined;
        }
        
        ret._id = undefined;
        ret.__v = undefined;
        return ret;
      },
    },
  },
);

// Index for efficient queries
DrawingSchema.index({ childId: 1, uploadedAt: -1 });

export const Drawing = model<IDrawing>('Drawing', DrawingSchema);
