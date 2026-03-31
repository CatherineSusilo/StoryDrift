import { Schema, model, Document, Types } from 'mongoose';

export interface IChildPreferences {
  storytellingTone: string;
  favoriteThemes: string[];
  defaultInitialState: string;
  personality?: string;
  favoriteMedia?: string;
  parentGoals?: string;
}

export interface IChild extends Document {
  userId: Types.ObjectId;
  name: string;
  age: number;
  dateOfBirth?: Date;
  avatar?: string;
  preferences?: IChildPreferences;
  createdAt: Date;
  updatedAt: Date;
}

const PreferencesSchema = new Schema<IChildPreferences>(
  {
    storytellingTone:    { type: String, default: 'calming' },
    favoriteThemes:      { type: [String], default: [] },
    defaultInitialState: { type: String, default: 'normal' },
    personality:         { type: String },
    favoriteMedia:       { type: String },
    parentGoals:         { type: String },
  },
  { _id: false },
);

const ChildSchema = new Schema<IChild>(
  {
    userId:      { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    name:        { type: String, required: true },
    age:         { type: Number, required: true },
    dateOfBirth: { type: Date },
    avatar:      { type: String },
    preferences: { type: PreferencesSchema, default: null },
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

export const Child = model<IChild>('Child', ChildSchema);
