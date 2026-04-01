import { Schema, model, Document, Types } from 'mongoose';

export interface IDrawing extends Document {
  userId: Types.ObjectId;
  childId: Types.ObjectId;
  name: string;
  imageData: Buffer;      // PNG image stored as binary
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
    imageData: { type: Buffer, required: true },  // Store PNG as binary blob
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
        // Convert binary buffer to base64 for JSON response
        if (ret.imageData) {
          ret.imageData = ret.imageData.toString('base64');
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
