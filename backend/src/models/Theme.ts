import { Schema, model, Document, Types } from 'mongoose';

export interface ITheme extends Document {
  userId: Types.ObjectId;
  name: string;
  description?: string;
  emoji?: string;
  imageUrl?: string;          // R2 URL of uploaded reference image
  imageDescription?: string;  // Claude-generated visual description for image gen prompts
  createdAt: Date;
  updatedAt: Date;
}

const ThemeSchema = new Schema<ITheme>(
  {
    userId:           { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    name:             { type: String, required: true },
    description:      { type: String },
    emoji:            { type: String },
    imageUrl:         { type: String },
    imageDescription: { type: String },
  },
  {
    timestamps: true,
    toJSON: {
      transform: (_doc, ret: any) => {
        ret.id = ret._id.toString();
        ret.userId = ret.userId?.toString();
        ret._id = undefined;
        ret.__v = undefined;
        return ret;
      },
    },
  },
);

ThemeSchema.index({ userId: 1, name: 1 });

export const Theme = model<ITheme>('Theme', ThemeSchema);
