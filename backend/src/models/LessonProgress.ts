import { Schema, model, Document, Types } from 'mongoose';

export interface ILessonProgress extends Document {
  childId: Types.ObjectId;
  lessonId: string;           // curriculum lesson id (e.g. "abc_01")
  sectionId: string;          // curriculum section id (e.g. "abc")
  completed: boolean;
  stars: number;              // 0-3 stars earned
  attempts: number;           // how many times this lesson was started
  bestScore: number;          // highest lesson_progress achieved (0-100)
  lastSessionId?: string;     // most recent story session id
  completedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

const LessonProgressSchema = new Schema<ILessonProgress>(
  {
    childId:       { type: Schema.Types.ObjectId, ref: 'Child', required: true, index: true },
    lessonId:      { type: String, required: true },
    sectionId:     { type: String, required: true },
    completed:     { type: Boolean, default: false },
    stars:         { type: Number, default: 0, min: 0, max: 3 },
    attempts:      { type: Number, default: 0 },
    bestScore:     { type: Number, default: 0 },
    lastSessionId: { type: String },
    completedAt:   { type: Date },
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

// One progress record per child per lesson
LessonProgressSchema.index({ childId: 1, lessonId: 1 }, { unique: true });
LessonProgressSchema.index({ childId: 1, sectionId: 1 });

export const LessonProgress = model<ILessonProgress>('LessonProgress', LessonProgressSchema);
