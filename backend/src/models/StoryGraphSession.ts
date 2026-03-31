import { Schema, model, Document, Types } from 'mongoose';

export interface IStoryGraphSession extends Document {
  childId: Types.ObjectId;
  mode: 'bedtime' | 'educational';
  state: any;
  lessonName?: string;
  startTime: Date;
  endTime?: Date;
  completed: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const StoryGraphSessionSchema = new Schema<IStoryGraphSession>(
  {
    _id:        { type: String } as any,
    childId:    { type: Schema.Types.ObjectId, ref: 'Child', required: true, index: true },
    mode:       { type: String, enum: ['bedtime', 'educational'], required: true },
    state:      { type: Schema.Types.Mixed, required: true },
    lessonName: { type: String },
    startTime:  { type: Date, default: Date.now, index: true },
    endTime:    { type: Date },
    completed:  { type: Boolean, default: false },
  },
  {
    timestamps: true,
    toJSON: {
      transform: (_doc, ret: any) => {
        ret.id = ret._id;
        ret.childId = ret.childId?.toString();
        ret.__v = undefined;
        return ret;
      },
    },
  },
);

export const StoryGraphSession = model<IStoryGraphSession>('StoryGraphSession', StoryGraphSessionSchema);
