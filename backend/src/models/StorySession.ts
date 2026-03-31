import { Schema, model, Document, Types } from 'mongoose';

export interface IStoryVitals {
  avgHeartRate: number;
  avgBreathingRate: number;
  minHeartRate: number;
  maxHeartRate: number;
  snapshots: any[];
  createdAt?: Date;
  updatedAt?: Date;
}

export interface IStorySession extends Document {
  childId: Types.ObjectId;
  storyTitle: string;
  storyContent: string;
  parentPrompt: string;
  storytellingTone: string;
  initialState: string;
  startTime: Date;
  endTime?: Date;
  duration?: number;
  sleepOnsetTime?: Date;
  completed: boolean;
  initialDriftScore: number;
  finalDriftScore: number;
  driftScoreHistory: number[];
  imagePrompts?: any;
  generatedImages: string[];
  audioUrls: string[];
  modelUsed?: string;
  targetDuration?: number;
  minigameFrequency?: string;
  imageJobId?: string;
  cameraEnabled?: boolean;
  avgHeartRate?: number;
  avgBreathingRate?: number;
  vitals?: IStoryVitals;
  createdAt: Date;
  updatedAt: Date;
}

const VitalsSchema = new Schema(
  {
    avgHeartRate:     { type: Number, default: 0 },
    avgBreathingRate: { type: Number, default: 0 },
    minHeartRate:     { type: Number, default: 0 },
    maxHeartRate:     { type: Number, default: 0 },
    snapshots:        { type: [Schema.Types.Mixed], default: [] },
    createdAt:        { type: Date, default: Date.now },
    updatedAt:        { type: Date, default: Date.now },
  },
  { _id: false },
);

const StorySessionSchema = new Schema<IStorySession>(
  {
    childId:           { type: Schema.Types.ObjectId, ref: 'Child', required: true, index: true },
    storyTitle:        { type: String, required: true },
    storyContent:      { type: String, required: true },
    parentPrompt:      { type: String, required: true },
    storytellingTone:  { type: String, required: true },
    initialState:      { type: String, required: true },
    startTime:         { type: Date, default: Date.now, index: true },
    endTime:           { type: Date },
    duration:          { type: Number },
    sleepOnsetTime:    { type: Date },
    completed:         { type: Boolean, default: false },
    initialDriftScore: { type: Number, default: 0 },
    finalDriftScore:   { type: Number, default: 0 },
    driftScoreHistory: { type: [Number], default: [] },
    imagePrompts:      { type: Schema.Types.Mixed },
    generatedImages:   { type: [String], default: [] },
    audioUrls:         { type: [String], default: [] },
    modelUsed:         { type: String },
    targetDuration:    { type: Number },
    minigameFrequency: { type: String },
    imageJobId:        { type: String },
    cameraEnabled:     { type: Boolean },
    avgHeartRate:      { type: Number },
    avgBreathingRate:  { type: Number },
    vitals:            { type: VitalsSchema, default: null },
  },
  {
    timestamps: true,
    toJSON: {
      transform: (_doc, ret: any) => {
        ret.id = ret._id.toString();
        ret.childId = ret.childId?.toString();
        ret._id = undefined;
        ret.__v = undefined;
        return ret;
      },
    },
  },
);

export const StorySession = model<IStorySession>('StorySession', StorySessionSchema);
