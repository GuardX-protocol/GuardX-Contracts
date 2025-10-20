# Deployment Scripts

This directory contains scripts for deploying and verifying the GuardX smart contracts using Hardhat Ignition.

## Scripts Overview

### 1. `deploy.ts` - Main Deployment Script
Deploys all GuardX contracts to any network using Hardhat Ignition.

**Usage:**
```bash
# Local deployment
npx hardhat run scripts/deploy.ts --network hardhat

# Testnet deployment (Sepolia)
npx hardhat run scripts/deploy.ts --network sepolia

# Mainnet deployment
npx hardhat run scripts/deploy.ts --network mainnet
```

**Features:**
- Deploys all 8 core contracts in correct order
- Automatically configures contract relationships
- Optionally adds supported tokens (via env vars)
- Saves deployment info to `deployments/` directory

**Environment Variables:**
- `PYTH_PRICE_FEED_ADDRESS` - Pyth oracle address (optional)
- `USDC_ADDRESS`, `USDT_ADDRESS`, `DAI_ADDRESS` - Token addresses to add as supported (optional)

### 2. `deploy-testnet.ts` - Testnet Deployment with Mocks
Deploys contracts with mock ERC20 tokens for testing purposes.

**Usage:**
```bash
# Deploy to local network with mocks
npx hardhat run scripts/deploy-testnet.ts --network hardhat

# Deploy to Sepolia with mocks
npx hardhat run scripts/deploy-testnet.ts --network sepolia
```

**Features:**
- Deploys mock USDC, USDT, and DAI tokens
- Deploys all core contracts
- Configures contracts and adds mock tokens as supported
- Mints test tokens to deployer
- Saves deployment info including mock token addresses

### 3. `verify.ts` - Contract Verification Helper
Generates verification commands for deployed contracts.

**Usage:**
```bash
# Auto-detect latest deployment
npx hardhat run scripts/verify.ts --network sepolia

# Specify deployment file
DEPLOYMENT_FILE=deployments/testnet-deployment-sepolia-xxx.json npx hardhat run scripts/verify.ts --network sepolia
```

**Features:**
- Auto-detects latest deployment file
- Generates ready-to-run verification commands
- Handles constructor arguments automatically
- Skips verification for local networks

## Deployment Flow

### For Local Development:
```bash
# 1. Start local node (optional)
npx hardhat node

# 2. Deploy contracts
npx hardhat run scripts/deploy.ts --network hardhat

# 3. Contracts are ready to use!
```

### For Testnet (Sepolia):
```bash
# 1. Set up environment variables
cp .env.example .env
# Edit .env with your PRIVATE_KEY and SEPOLIA_RPC_URL

# 2. Deploy with mocks
npx hardhat run scripts/deploy-testnet.ts --network sepolia

# 3. Verify contracts
npx hardhat run scripts/verify.ts --network sepolia
# Copy and run the generated commands
```

### For Mainnet:
```bash
# 1. Ensure environment is configured
# Set PRIVATE_KEY, MAINNET_RPC_URL, and token addresses

# 2. Deploy contracts
npx hardhat run scripts/deploy.ts --network mainnet

# 3. Verify contracts
npx hardhat run scripts/verify.ts --network mainnet
```

## Deployment Artifacts

All deployments are saved to the `deployments/` directory with the following format:

```json
{
  "network": "sepolia",
  "timestamp": "2025-10-20T12:30:08.245Z",
  "mockTokens": {
    "USDC": "0x...",
    "USDT": "0x...",
    "DAI": "0x..."
  },
  "contracts": {
    "PythPriceMonitor": "0x...",
    "DEXAggregator": "0x...",
    "CrashGuardCore": "0x...",
    "EmergencyExecutor": "0x...",
    "LitRelayContract": "0x...",
    "LitProtocolIntegration": "0x...",
    "CrossChainManager": "0x...",
    "CrossChainEmergencyCoordinator": "0x..."
  }
}
```

## Ignition Modules

The deployment logic is defined in Ignition modules located in `ignition/modules/`:

- `CrashGuardSystem.ts` - Main production deployment module
- `TestnetDeployment.ts` - Testnet deployment with mock tokens

These modules define:
- Contract deployment order
- Constructor arguments
- Configuration calls
- Dependencies between contracts

## Troubleshooting

### "Insufficient funds" error
Make sure your deployer account has enough ETH for gas fees.

### "Network not configured" error
Check your `hardhat.config.ts` and ensure the network is properly configured with RPC URL and accounts.

### Verification fails
- Ensure you're using the correct network
- Check that the contract is deployed and the address is correct
- Verify constructor arguments match the deployment
- Some networks may have delays before verification is available

## Gas Estimates

Approximate gas costs for full deployment:

- **Local/Hardhat**: ~15-16M gas (free)
- **Sepolia**: ~15-16M gas (~0.001-0.01 ETH depending on gas price)
- **Mainnet**: ~15-16M gas (varies with gas price)

Individual contract estimates:
- PythPriceMonitor: ~1.5M gas
- DEXAggregator: ~1.2M gas
- CrashGuardCore: ~2.5M gas
- EmergencyExecutor: ~2.0M gas
- LitRelayContract: ~1.8M gas
- LitProtocolIntegration: ~1.5M gas
- CrossChainManager: ~2.0M gas
- CrossChainEmergencyCoordinator: ~2.5M gas
- Configuration: ~500K gas
