// Core domain types matching backend
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
  totalValue: bigint;
  lastUpdated: Date;
  riskScore: number;
}

export interface Asset {
  tokenAddress: string;
  symbol: string;
  amount: bigint;
  valueUSD: bigint;
  riskLevel: RiskLevel;
}

export interface ProtectionPolicy {
  userId: string;
  crashThreshold: number;
  maxSlippage: number;
  emergencyActions: EmergencyAction[];
  stablecoinPreference: string;
  gasLimit: bigint;
}

export interface PriceData {
  tokenAddress: string;
  price: bigint;
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
  gasUsed?: bigint;
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

// UI specific types
export interface TokenBalance {
  tokenAddress: string;
  symbol: string;
  balance: bigint;
  decimals: number;
  name: string;
  logoUri?: string;
}

export interface WalletConnection {
  address: string;
  chainId: number;
  isConnected: boolean;
  isConnecting: boolean;
  connector?: any;
}

export interface DashboardData {
  portfolio: Portfolio;
  riskIndicators: RiskIndicators;
  recentTransactions: Transaction[];
  protectionStatus: ProtectionStatus;
}

export interface RiskIndicators {
  currentRiskScore: number;
  riskLevel: RiskLevel;
  crashProbability: number;
  lastUpdated: Date;
}

export interface ProtectionStatus {
  isActive: boolean;
  lastTriggered?: Date;
  totalProtections: number;
  policy: ProtectionPolicy;
}

// Component props types
export interface ButtonProps {
  variant?: 'primary' | 'secondary' | 'outline' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
  loading?: boolean;
  disabled?: boolean;
  children: React.ReactNode;
  onClick?: () => void;
  className?: string;
}

export interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  size?: 'sm' | 'md' | 'lg' | 'xl';
}

// API types
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
  totalValueConverted: bigint;
  slippageIncurred: number;
}

export interface AuditTrailEntry {
  action: string;
  timestamp: Date;
  details: Record<string, any>;
  userApproved?: boolean;
  transactionHash?: string;
  gasUsed?: bigint;
  executionResult: ExecutionResult;
}

export interface ExecutionResult {
  success: boolean;
  transactionHash?: string;
  gasUsed?: bigint;
  error?: string;
}