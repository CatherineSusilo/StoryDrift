import { Schema, model, Document, Types } from 'mongoose';

export interface ISleepSession extends Document {
  childId: Types.ObjectId;
  storySessionId?: Types.ObjectId;
  bedtime: Date;
  wakeupTime?: Date;
  duration?: number;
  quality?: 'poor' | 'fair' | 'good' | 'excellent';
  notes?: string;
  timeToSleep?: number;
  nightWakings: number;
  sleepEfficiency?: number;
  weatherCondition?: string;
  roomTemperature?: number;
  createdAt: Date;
  updatedAt: Date;
}

const SleepSessionSchema = new Schema<ISleepSession>(
  {
    childId:          { type: Schema.Types.ObjectId, ref: 'Child', required: true, index: true },
    storySessionId:   { type: Schema.Types.ObjectId, ref: 'StorySession' },
    bedtime:          { type: Date, required: true, index: true },
    wakeupTime:       { type: Date },
    duration:         { type: Number },
    quality:          { type: String, enum: ['poor', 'fair', 'good', 'excellent'] },
    notes:            { type: String },
    timeToSleep:      { type: Number },
    nightWakings:     { type: Number, default: 0 },
    sleepEfficiency:  { type: Number },
    weatherCondition: { type: String },
    roomTemperature:  { type: Number },
  },
  {
    timestamps: true,
    toJSON: {
      transform: (_doc, ret: any) => {
        ret.id = ret._id.toString();
        ret.childId = ret.childId?.toString();
        if (ret.storySessionId) ret.storySessionId = ret.storySessionId.toString();
        ret._id = undefined;
        ret.__v = undefined;
        return ret;
      },
    },
  },
);

export const SleepSession = model<ISleepSession>('SleepSession', SleepSessionSchema);
