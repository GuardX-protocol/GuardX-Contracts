import dotenv from 'dotenv';

dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  
  // Database
  mongodbUri: process.env.MONGODB_URI || 'mongodb://localhost:27017/guardx',
  redisUrl: process.env.REDIS_URL || 'redis://localhost:6379',
  
  // JWT
  jwtSecret: process.env.JWT_SECRET || 'your-secret-key',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '24h',
  
  // Blockchain
  ethereumRpcUrl: process.env.ETHEREUM_RPC_URL || 'http://localhost:8545',
  privateKey: process.env.PRIVATE_KEY || '',
  
  // External Services
  pythNetworkUrl: process.env.PYTH_NETWORK_URL || 'https://hermes.pyth.network',
  vincentSdkApiKey: process.env.VINCENT_SDK_API_KEY || '',
  
  // Rate Limiting
  rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000', 10), // 15 minutes
  rateLimitMaxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100', 10),
  
  // Monitoring
  monitoringIntervalMs: parseInt(process.env.MONITORING_INTERVAL_MS || '600000', 10), // 10 minutes
  
  // CORS
  corsOrigin: process.env.CORS_ORIGIN || 'http://localhost:5173',
} as const;

// Validate required environment variables
const requiredEnvVars = ['JWT_SECRET', 'ETHEREUM_RPC_URL'];

for (const envVar of requiredEnvVars) {
  if (!process.env[envVar]) {
    throw new Error(`Required environment variable ${envVar} is not set`);
  }
}