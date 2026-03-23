import { Express } from 'express';

declare global {
  namespace Express {
    interface Request {
      auth?: {
        sub: string;
        payload: any;
      };
    }
  }
}
