import { Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config/environment';
import { createError } from './errorHandler';
import { JWTPayload, AuthenticatedRequest } from '../types';

export const authMiddleware = (req: AuthenticatedRequest, _res: Response, next: NextFunction): void => {
  try {
    const authHeader = req.headers.authorization as string | undefined;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw createError('Access token is required', 401);
    }

    const token = authHeader.substring(7);
    
    const decoded = jwt.verify(token, config.jwtSecret) as JWTPayload;
    
    // Add user info to request object
    req.user = {
      id: decoded.userId,
      address: decoded.address,
      createdAt: new Date(),
      lastActive: new Date(),
      kycStatus: 'pending' as any, // Will be fetched from database in actual implementation
    };

    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      next(createError('Invalid access token', 401));
    } else {
      next(error);
    }
  }
};

export const generateToken = (userId: string, address: string): string => {
  return jwt.sign(
    { userId, address },
    config.jwtSecret,
    { expiresIn: config.jwtExpiresIn } as jwt.SignOptions
  );
};