# GuardX Smart Contracts

Smart contract infrastructure for automated DeFi crash protection with cross-chain capabilities.

## 🚀 Latest Updates

### New Features
- ✅ **Configurable Minimum Deposits**: 1 stablecoin or 0.01 for other tokens
- ✅ **Client-Side Configuration**: Users set crash thresholds and max slippage
- ✅ **Real-Time Pyth Integration**: 60-second price freshness for crash detection
- ✅ **Optimized Lit Protocol**: Automated PKP-based emergency protection

📖 **[Quick Start Guide](./contracts/docs/QUICK_START.md)** | **[Complete Updates](./contracts/docs/UPDATES_SUMMARY.md)**

## Overview

GuardX provides a decentralized crash protection system for DeFi portfolios through a suite of Solidity smart contracts. The platform monitors real-time price feeds via Pyth Network oracles and executes automated emergency protection actions when market crash conditions are detected. The system supports cross-chain operations through Lit Protocol integration and programmable key pairs (PKPs).

### Key Features

- **Flexible Deposits**: Minimum 1 stablecoin or 0.01 tokens
- **User-Controlled**: Set your own crash thresholds (0.01% - 100%)
- **Real-Time Monitoring**: Pyth Network prices updated every 30-60 seconds
- **Automated Protection**: Lit Protocol PKPs execute emergency actions
- **Cross-Chain Support**: Protect assets across multiple networks

## Architecture

### Core Contracts

**CrashGuardCore.sol**
- Primary contract for asset management and protection policies
- Handles ETH and ERC20 token deposits and withdrawals
- Manages user protection configurations and thresholds
- Emits events for monitoring and off-chain integrations

**EmergencyExecutor.sol**
- Executes emergency protection actions during market crashes
- Performs asset conversions and liquidations
- Implements slippage protection and MEV resistance
- Supports batch operations for gas efficiency

**PythPriceMonitor.sol**
- Integrates with Pyth Network for real-time price feeds
- Monitors multiple asset prices simultaneously
- Detects crash conditions based on configurable thresholds
- Provides price validation and staleness checks

**DEXAggregator.sol**
- Placeholder for decentralized exchange aggregation
- Designed for optimal swap routing and execution
- Supports multiple DEX protocols

### Cross-Chain Infrastructure

**LitProtocolIntegration.sol**
- Manages PKP authentication and authorization
- Enables programmable cryptography for decentralized key management
- Supports conditional access control via Lit Actions

**LitRelayContract.sol**
- Handles cross-chain message relay and verification
- Validates PKP signatures for cross-chain operations
- Manages cross-chain state synchronization

**CrossChainManager.sol**
- Coordinates asset locking and migration across chains
- Tracks cross-chain asset movements
- Implements security checks for cross-chain transfers

**CrossChainEmergencyCoordinator.sol**
- Orchestrates emergency actions across multiple chains
- Synchronizes protection policies between chains
- Manages multi-chain crash detection and response

## Prerequisites

- Node.js 18 or higher
- pnpm package manager
- Git

## Installation

```bash
cd contracts
pnpm install
```

## Configuration

Create a `.env` file in the contracts directory:

```bash
cp .env.example .env
```

Required environment variables:

```
PRIVATE_KEY=                    # Deployment wallet private key
SEPOLIA_RPC_URL=               # Sepolia testnet RPC endpoint
MAINNET_RPC_URL=               # Ethereum mainnet RPC endpoint
ARBITRUM_RPC_URL=              # Arbitrum RPC endpoint
POLYGON_RPC_URL=               # Polygon RPC endpoint
BASE_RPC_URL=                  # Base RPC endpoint
ETHERSCAN_API_KEY=             # Etherscan API key for verification
ARBISCAN_API_KEY=              # Arbiscan API key
POLYGONSCAN_API_KEY=           # Polygonscan API key
BASESCAN_API_KEY=              # Basescan API key
REPORT_GAS=false               # Enable gas reporting
```

## Development

### Compile Contracts

```bash
npx hardhat compile
```

### Run Tests

```bash
# Run all tests
pnpm test

# Run with gas reporting
pnpm run test:gas

# Generate coverage report
pnpm run test:coverage
```

### Local Development

Start a local Hardhat node:

```bash
pnpm run dev
```

In a separate terminal, deploy contracts to local network:

```bash
npx hardhat run scripts/deploy.ts --network hardhat
```

### Linting

```bash
# Check for issues
pnpm run lint

# Auto-fix issues
pnpm run lint:fix
```

## Deployment

### Testnet Deployment

Deploy to Sepolia testnet:

```bash
npx hardhat run scripts/deploy.ts --network sepolia
```

### Mainnet Deployment

Deploy to Ethereum mainnet:

```bash
npx hardhat run scripts/deploy.ts --network mainnet
```

### Multi-Chain Deployment

Deploy to specific networks:

```bash
# Arbitrum
npx hardhat run scripts/deploy.ts --network arbitrum

# Polygon
npx hardhat run scripts/deploy.ts --network polygon
```

### Contract Verification

After deployment, verify contracts on block explorers:

```bash
# Verify on Hardhat (local)
npx hardhat run scripts/verify.ts --network hardhat

# Verify on Sepolia
npx hardhat run scripts/verify.ts --network sepolia

# Verify on mainnet
npx hardhat run scripts/verify.ts --network mainnet
```

Deployment artifacts are saved in the `deployments/` directory with network-specific information.

## How It Works

### 1. Asset Protection Setup

Users deposit assets into CrashGuardCore and configure protection policies:

- **Minimum Deposits**: 
  - Stablecoins: 1 token (e.g., 1 USDC)
  - Other tokens: 0.01 tokens (e.g., 0.01 ETH)
- **Crash Threshold**: 0.01% - 100% (client-configurable, in basis points)
- **Max Slippage**: Up to 50% (client-configurable, in basis points)
- **Stablecoin Preference**: Target stablecoin for asset conversion
- **Gas Limit**: Maximum gas for emergency execution

```javascript
// Example: Deposit and configure
await crashGuardCore.depositAsset(USDC_ADDRESS, 1_000_000); // 1 USDC

await crashGuardCore.setProtectionPolicy({
  crashThreshold: 2000,              // 20% drop triggers protection
  maxSlippage: 500,                  // 5% max slippage
  stablecoinPreference: USDC_ADDRESS,
  gasLimit: 500000
});
```

### 2. Real-Time Price Monitoring

PythPriceMonitor continuously tracks asset prices with real-time data:

- **Real-Time Updates**: Fetches prices from Pyth Hermes API every 30-60 seconds
- **60-Second Freshness**: Ensures crash detection uses recent data
- **Historical Tracking**: Maintains price history for trend analysis
- **Automatic Fallback**: Uses cached prices if real-time unavailable
- **Staleness Detection**: Alerts when prices become outdated

```javascript
// Update prices with real-time data
const vaas = await fetchFromHermes(priceIds);
await pythMonitor.updatePricesRealtime(vaas, { value: updateFee });

// Check real-time price
const price = await pythMonitor.getRealtimePrice(priceId);
```

### 3. Emergency Execution

When a crash is detected, EmergencyExecutor automatically:

- Validates crash conditions and user authorization
- Executes asset conversions to stablecoins
- Applies slippage protection and MEV resistance
- Records all actions for audit trails

### 4. Automated Lit Protocol Protection

Lit Protocol enables fully automated emergency protection:

- **PKP Creation**: Users create Programmable Key Pairs
- **Lit Actions**: JavaScript code monitors prices and conditions
- **Automatic Signing**: PKPs sign emergency transactions when crash detected
- **Decentralized**: No single point of control or failure

```javascript
// Setup PKP authorization
await crashGuardCore.setupPKPAuthorization(
  userAddress,
  pkpAddress,
  litActionIPFSHash
);

// Lit Action monitors and executes automatically
// See docs/LIT_PROTOCOL_GUIDE.md for complete setup
```

### 5. Cross-Chain Protection

For multi-chain portfolios:

- LitProtocolIntegration authenticates users via PKPs
- CrossChainManager locks assets and initiates migrations
- LitRelayContract verifies and relays cross-chain messages
- CrossChainEmergencyCoordinator synchronizes protection across chains

## Testing

The test suite covers:

- Asset deposit and withdrawal flows
- Protection policy management
- Emergency execution scenarios
- Cross-chain operations
- Access control and authorization
- Edge cases and failure modes

Test files are located in `test/`:

- `CrashGuardCore.test.ts` - Core functionality tests
- `EmergencyExecutor.test.ts` - Emergency action tests
- `LitProtocol.test.ts` - Cross-chain and PKP tests
- `CoreContracts.test.ts` - Integration tests

## Security Considerations

- All state-changing functions implement reentrancy protection
- Access control enforced via owner and role-based permissions
- Input validation on all external calls
- Safe math operations via Solidity 0.8+ overflow protection
- Comprehensive event logging for monitoring

## Gas Optimization

Contracts are optimized for gas efficiency:

- Compiler optimization enabled (200 runs)
- Efficient storage patterns and packing
- Batch operations to reduce transaction costs
- Minimal external calls and storage reads

## 📚 Documentation

- **[Quick Start Guide](./contracts/docs/QUICK_START.md)** - Get started in 5 minutes
- **[Updates Summary](./contracts/docs/UPDATES_SUMMARY.md)** - Complete feature overview
- **[Lit Protocol Guide](./contracts/docs/LIT_PROTOCOL_GUIDE.md)** - Automated protection setup
- **[Pyth Real-Time Guide](./contracts/docs/PYTH_REALTIME_GUIDE.md)** - Price integration details

## Project Structure

```
contracts/
├── contracts/
│   ├── interfaces/                    # Contract interfaces
│   ├── CrashGuardCore.sol            # Main asset management (UPDATED)
│   ├── PythPriceMonitor_v2.sol       # Real-time price monitoring (NEW)
│   ├── PythPriceMonitor.sol          # Legacy price monitoring
│   ├── LitProtocolIntegration.sol    # PKP management
│   ├── EmergencyExecutor.sol         # Emergency actions
│   ├── DEXAggregator.sol             # DEX integration
│   ├── LitRelayContract.sol          # Cross-chain relay
│   ├── CrossChainManager.sol         # Asset migration
│   ├── CrossChainEmergencyCoordinator.sol
│   └── MockERC20.sol                 # Testing utility
├── scripts/
│   ├── deploy.ts                     # Main deployment script
│   ├── deploy-testnet.ts             # Testnet deployment
│   ├── monitor-system.js             # Complete monitoring system (NEW)
│   ├── updatePythPrices.ts           # Update prices on-chain
│   └── verify.ts                     # Contract verification
├── docs/                             # Documentation (NEW)
│   ├── QUICK_START.md               # Quick start guide
│   ├── UPDATES_SUMMARY.md           # Feature updates
│   ├── LIT_PROTOCOL_GUIDE.md        # Lit Protocol integration
│   └── PYTH_REALTIME_GUIDE.md       # Pyth Network guide
├── test/                             # Test suite
├── deployments/                      # Deployment artifacts
├── config.example.json               # Configuration template (NEW)
└── hardhat.config.ts                 # Hardhat configuration
```

## Technology Stack

- Solidity 0.8.20
- Hardhat 3.0+
- OpenZeppelin Contracts 4.9.6
- Pyth Network SDK
- Lit Protocol SDK
- TypeScript
- Ethers.js v6

## License

MIT License