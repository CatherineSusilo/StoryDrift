import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';

export const errorHandler = (
  err: any,
  req: Request,
  res: Response,
  next: NextFunction
) => {
  console.error('Error:', err);

  // Zod validation errors
  if (err instanceof ZodError) {
    return res.status(400).json({
      error: 'Validation error',
      details: err.errors,
    });
  }

  // JWT / Auth errors (express-oauth2-jwt-bearer sets err.status)
  const status = err.status ?? err.statusCode ?? 500;
  if (status === 401 || status === 403) {
    return res.status(status).json({ error: 'Unauthorized' });
  }

  // Default error response
  res.status(status).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined,
  });
};
