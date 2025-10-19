# GuardX Smart Contracts

This directory contains the smart contracts for the GuardX DeFi crash protection platform, built with Hardhat 3.0+ and Solidity 0.8.20.

## Overview

GuardX provides automated crash protection for DeFi portfolios using:
- Real-time price monitoring via Pyth Network
- Automated emergency execution during market crashes
- Cross-chain protection via Lit Protocol
- Programmable cryptography for decentralized key management

## Contracts Architecture

### Core Contracts
- **CrashGuardCore.sol** - Main contract for asset deposits, withdrawals, and protection policies
- **EmergencyExecutor.sol** - Handles emergency protection actions and asset conversions
- **PythPriceMonitor.sol** - Integrates with Pyth Network for real-time price feeds
- **DEXAggregator.sol** - Placeholder for DEX aggregation functionality

### Lit Protocol Integration
- **LitRelayContract.sol** - Cross-chain messaging and PKP signature verification
- **LitProtocolIntegration.sol** - PKP authentication and conditional access
- **CrossChainManager.sol** - Cross-chain asset management and migrations
- **CrossChainEmergencyCoordinator.sol** - Multi-chain emergency coordination

### Interfaces
All contracts implement well-defined interfaces located in `contracts/interfaces/`

## Setup

### Prerequisites
- Node.js 18+
- npm or pnpm
- Git

### Installation

```bash
# Install dependencies
npm install

# Copy environment template
cp .env.example .env

# Edit .env with your configuration
nano .env
```

### Environment Variables

```bash
# Private key for deployment (without 0x prefix)
PRIVATE_KEY=your_private_key_here

# RPC URLs
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_infura_key
MAINNET_RPC_URL=https://mainnet.infura.io/v3/your_infura_key
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
POLYGON_RPC_URL=https://polygon-rpc.com

# API Keys for contract verification
ETHERSCAN_API_KEY=your_etherscan_api_key
ARBISCAN_API_KEY=your_arbiscan_api_key
POLYGONSCAN_API_KEY=your_polygonscan_api_key

# Gas reporting
REPORT_GAS=false
COINMARKETCAP_API_KEY=your_coinmarketcap_api_key
```

## Development

### Compile Contracts
```bash
npm run build
```

### Run Tests
```bash
# Run all tests
npm test

# Run tests with gas reporting
npm run test:gas

# Run coverage analysis
npm run test:coverage
```

### Local Development
```bash
# Start local Hardhat node
npm run dev

# Deploy to local network (in another terminal)
npm run deploy:local
```

## Deployment

### Testnet Deployment (Sepolia)
```bash
npm run deploy:testnet
```

### Mainnet Deployment
```bash
npm run deploy:mainnet
```

### Multi-chain Deployment
```bash
# Deploy to Arbitrum
npm run deploy:arbitrum

# Deploy to Polygon
npm run deploy:polygon
```

## Contract Verification

After deployment, verify contracts on block explorers:

```bash
# Verify on Sepolia
npm run verify:sepolia -- deployments/testnet-deployment-11155111-<timestamp>.json

# Verify on Mainnet
npm run verify:mainnet -- deployments/deployment-1-<timestamp>.json
```

## Testing

The test suite includes comprehensive tests for:

### CrashGuardCore Tests
- Asset deposits and withdrawals (ETH and ERC20)
- Protection policy management
- Emergency functions
- Access control

### EmergencyExecutor Tests
- Emergency protection execution
- Asset conversion functionality
- Batch operations
- Access control and authorization

### Lit Protocol Tests
- PKP registration and management
- Lit Action execution
- Cross-chain messaging
- Asset locking and migration

### Running Specific Tests
```bash
# Run specific test file
npx hardhat test test/CrashGuardCore.test.ts

# Run tests with specific network
npx hardhat test --network hardhat

# Run tests with gas reporting
REPORT_GAS=true npx hardhat test
```

## Gas Optimization

The contracts are optimized for gas efficiency:
- OpenZeppelin's gas-optimized libraries
- Efficient storage patterns
- Minimal external calls
- Batch operations support

### Gas Reports
```bash
npm run test:gas
```

## Security Considerations

### Access Control
- Owner-based access control for administrative functions
- Role-based permissions for emergency executors
- PKP-based authorization for cross-chain operations

### Reentrancy Protection
- ReentrancyGuard on all state-changing functions
- Checks-Effects-Interactions pattern

### Input Validation
- Comprehensive input validation
- Safe math operations via Solidity 0.8+
- Custom error messages for better debugging

## Deployment Artifacts

Deployment information is automatically saved to `deployments/` directory:
- Contract addresses
- Constructor arguments
- Network information
- Deployment timestamp

## Integration Examples

### Basic Portfolio Protection
```solidity
// 1. Deposit assets
crashGuardCore.depositAsset(tokenAddress, amount);

// 2. Set protection policy
ProtectionPolicy memory policy = ProtectionPolicy({
    crashThreshold: 2000, // 20% crash threshold
    maxSlippage: 1000,    // 10% max slippage
    emergencyActions: [],
    stablecoinPreference: usdcAddress,
    gasLimit: 500000
});
crashGuardCore.setProtectionPolicy(policy);

// 3. Emergency protection is now active
```

### Cross-Chain Protection
```solidity
// 1. Set up PKP authentication
litProtocolIntegration.authenticateWithPKP(user, pkpAuth, signature);

// 2. Lock assets for cross-chain operation
crossChainManager.lockAsset(user, token, amount, targetChainId);

// 3. Initiate cross-chain migration
crossChainManager.initiateCrossChainMigration(user, token, amount, targetChainId);
```

## Troubleshooting

### Common Issues

1. **Compilation Errors**
   ```bash
   npm run clean
   npm run build
   ```

2. **Test Failures**
   - Check network configuration
   - Ensure sufficient test ETH
   - Verify contract dependencies

3. **Deployment Issues**
   - Verify RPC URL and private key
   - Check gas settings
   - Ensure sufficient balance

### Debug Mode
```bash
# Enable Hardhat debug mode
DEBUG=hardhat:* npx hardhat test
```

## Contributing

1. Follow Solidity style guide
2. Add comprehensive tests for new features
3. Update documentation
4. Run linting and tests before submitting

```bash
# Lint contracts
npm run lint

# Fix linting issues
npm run lint:fix
```

## License

MIT License - see LICENSE file for details.

## Support

For technical support and questions:
- GitHub Issues: [Create an issue](https://github.com/guardx/contracts/issues)
- Documentation: [docs.guardx.io](https://docs.guardx.io)
- Discord: [Join our community](https://discord.gg/guardx)