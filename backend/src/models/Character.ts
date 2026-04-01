import { Schema, model, Document, Types } from 'mongoose';

export interface ICharacter extends Document {
  childId: Types.ObjectId;
  userId: Types.ObjectId;
  name: string;
  description: string;    // physical appearance (1-2 sentences)
  temperament: string;    // personality traits (1-2 sentences)
  imageUrl: string;         // permanent R2 URL of reference portrait
  falImageUrl: string;      // ephemeral fal.ai CDN URL (kept for compatibility)
  imageDescription: string; // Claude vision analysis — passed to image gen prompts
  createdAt: Date;
  updatedAt: Date;
}

const CharacterSchema = new Schema<ICharacter>(
  {
    childId:     { type: Schema.Types.ObjectId, ref: 'Child', required: true, index: true },
    userId:      { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    name:        { type: String, required: true },
    description: { type: String, required: true },
    temperament: { type: String, required: true },
    imageUrl:         { type: String, required: true },
    falImageUrl:      { type: String, default: '' },
    imageDescription: { type: String, default: '' }, // Claude vision analysis — used in image gen prompts
  },
  {
    timestamps: true,
    toJSON: {
      transform: (_doc, ret: any) => {
        ret.id = ret._id.toString();
        ret.childId = ret.childId?.toString();
        ret.userId = ret.userId?.toString();
        ret._id = undefined;
        ret.__v = undefined;
        return ret;
      },
    },
  },
);

CharacterSchema.index({ childId: 1, name: 1 });

export const Character = model<ICharacter>('Character', CharacterSchema);
