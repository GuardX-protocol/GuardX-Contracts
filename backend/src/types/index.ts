import { BigNumberish } from 'ethers';
import { Request } from 'express';

// Core domain types
export interface User {
  id: string;
  address: string;
  vincentWalletId?: string;
  createdAt: Date;
  lastActive: Date;
  kycStatus: KYCStatus;
}

export interface Portfolio {
  userId: string;
  assets: Asset[];
  totalValue: BigNumberish;
  lastUpdated: Date;
  riskScore: number;
}

export interface Asset {
  tokenAddress: string;
  symbol: string;
  amount: BigNumberish;
  valueUSD: BigNumberish;
  riskLevel: RiskLevel;
}

export interface ProtectionPolicy {
  userId: string;
  crashThreshold: number;
  maxSlippage: number;
  emergencyActions: EmergencyAction[];
  stablecoinPreference: string;
  gasLimit: BigNumberish;
}

export interface PriceData {
  tokenAddress: string;
  price: BigNumberish;
  timestamp: Date;
  confidence: number;
  source: 'pyth' | 'chainlink' | 'fallback';
}

export interface Transaction {
  id: string;
  userId: string;
  type: TransactionType;
  status: TransactionStatus;
  hash?: string;
  gasUsed?: BigNumberish;
  timestamp: Date;
  metadata: Record<string, any>;
  automatedAction: boolean;
  emergencyExecution?: EmergencyExecutionDetails;
  auditTrail: AuditTrailEntry[];
}

// Enums
export enum KYCStatus {
  PENDING = 'pending',
  VERIFIED = 'verified',
  REJECTED = 'rejected',
}

export enum RiskLevel {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high',
  CRITICAL = 'critical',
}

export enum TransactionType {
  DEPOSIT = 'deposit',
  WITHDRAWAL = 'withdrawal',
  EMERGENCY_CONVERSION = 'emergency_conversion',
  POLICY_UPDATE = 'policy_update',
}

export enum TransactionStatus {
  PENDING = 'pending',
  CONFIRMED = 'confirmed',
  FAILED = 'failed',
  CANCELLED = 'cancelled',
}

// API Response types
export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface ValidationResult {
  isValid: boolean;
  errors: ValidationError[];
}

export interface ValidationError {
  field: string;
  message: string;
  code: string;
}

// Service interfaces
export interface EmergencyAction {
  type: string;
  parameters: Record<string, any>;
}

export interface EmergencyExecutionDetails {
  triggeredAt: Date;
  reason: string;
  assetsConverted: Asset[];
  totalValueConverted: BigNumberish;
  slippageIncurred: number;
}

export interface AuditTrailEntry {
  action: string;
  timestamp: Date;
  details: Record<string, any>;
  userApproved?: boolean;
  transactionHash?: string;
  gasUsed?: BigNumberish;
  executionResult: ExecutionResult;
}

export interface ExecutionResult {
  success: boolean;
  transactionHash?: string;
  gasUsed?: BigNumberish;
  error?: string;
}

// Authentication types
export interface JWTPayload {
  userId: string;
  address: string;
  iat: number;
  exp: number;
}

export interface AuthenticatedRequest extends Request {
  user?: User;
}