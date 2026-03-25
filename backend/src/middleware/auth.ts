import { Request, Response, NextFunction } from 'express';
import { auth } from 'express-oauth2-jwt-bearer';
import dotenv from 'dotenv';

// Ensure environment variables are loaded
dotenv.config();

// Validate required environment variables
if (!process.env.AUTH0_AUDIENCE) {
  throw new Error('AUTH0_AUDIENCE is required in .env file');
}
if (!process.env.AUTH0_DOMAIN) {
  throw new Error('AUTH0_DOMAIN is required in .env file');
}

// Auth0 JWT validation middleware with detailed logging
const jwtCheck = auth({
  audience: process.env.AUTH0_AUDIENCE,
  issuerBaseURL: `https://${process.env.AUTH0_DOMAIN}`,
  tokenSigningAlg: 'RS256',
});

export const authMiddleware = (req: Request, res: Response, next: NextFunction) => {
  console.log('\n🔒 Auth Middleware Check:');
  console.log('📍 Endpoint:', req.method, req.path);
  console.log('🎫 Authorization header:', req.headers.authorization ? 'Present (Bearer ...)' : 'MISSING');
  console.log('🎯 Expected audience:', process.env.AUTH0_AUDIENCE);
  console.log('🏢 Expected issuer:', `https://${process.env.AUTH0_DOMAIN}`);

  jwtCheck(req, res, (err) => {
    if (err) {
      console.error('❌ JWT Validation Failed:', err instanceof Error ? err.message : String(err));
      console.error('   Status:', err.status || 401);
      console.error('   Code:', err.code);
      return next(err);
    }

    console.log('✅ JWT Validation Passed');
    console.log('📦 Full req.auth object:', JSON.stringify((req as any).auth, null, 2));
    console.log('👤 User sub:', (req as any).auth?.sub);
    console.log('👤 User payload:', (req as any).auth?.payload);
    next();
  });
};

// Extended Request interface with auth
export interface AuthRequest extends Request {
  auth?: {
    payload: {
      sub: string; // Auth0 user ID
      [key: string]: any;
    };
    header: any;
    token: string;
  };
}

// Middleware to extract user info from JWT
export const extractUser = (req: AuthRequest, res: Response, next: NextFunction) => {
  if (!req.auth?.payload?.sub) {
    console.error('❌ extractUser: No sub found in token payload');
    return res.status(401).json({ error: 'Unauthorized' });
  }
  console.log('✅ extractUser: User authenticated:', req.auth.payload.sub);
  next();
};
