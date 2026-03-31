import { Schema, model, Document } from 'mongoose';

export interface IUser extends Document {
  auth0Id: string;
  email: string;
  name?: string;
  picture?: string;
  createdAt: Date;
  updatedAt: Date;
}

const UserSchema = new Schema<IUser>(
  {
    auth0Id:  { type: String, required: true, unique: true, index: true },
    email:    { type: String, required: true, unique: true },
    name:     { type: String },
    picture:  { type: String },
  },
  {
    timestamps: true,
    toJSON: {
      transform: (_doc, ret: any) => {
        ret.id = ret._id.toString();
        ret._id = undefined;
        ret.__v = undefined;
        return ret;
      },
    },
  },
);

export const User = model<IUser>('User', UserSchema);
