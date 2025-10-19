# GuardX DeFi Platform

Advanced DeFi crash protection platform with automated emergency response capabilities.

## Overview

GuardX is a comprehensive DeFi protection platform that enables users to deposit ETH and ERC20 assets into a secure smart contract system. The platform leverages real-time Pyth Network price feeds to detect multi-asset market crashes and automatically executes emergency protection actions, including selling risky assets and converting them to stablecoins through optimized DEX swaps.

## Architecture

The platform consists of three main components:

- **Smart Contracts** (`/contracts`): Solidity contracts for asset management, price monitoring, and emergency execution
- **Backend Services** (`/backend`): Node.js/TypeScript API server with monitoring and execution services
- **Frontend Application** (`/frontend`): React/Vite application with responsive design and real-time updates

## Features

- 🛡️ **Automated Crash Protection**: Real-time monitoring with emergency asset conversion
- 🔗 **Vincent Wallet Integration**: Secure delegation for automated transactions
- 📊 **Pyth Network Oracles**: High-frequency, low-latency price feeds
- 🎯 **MEV Protection**: Advanced slippage and front-running protection
- 📱 **Mobile-First Design**: Responsive interface optimized for all devices
- 🔍 **Comprehensive Audit Trail**: Complete transaction logging and compliance reporting

## Quick Start

### Prerequisites

- Node.js 18+ and npm 9+
- MongoDB (for backend data storage)
- Redis (for job queuing)
- Ethereum development environment (Hardhat)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd guardx-defi-platform
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Start development servers**
   ```bash
   npm run dev
   ```

This will start:
- Smart contracts development node on `http://localhost:8545`
- Backend API server on `http://localhost:3000`
- Frontend application on `http://localhost:5173`

### Individual Component Setup

#### Smart Contracts
```bash
cd contracts
npm install
npm run build
npm run test
npm run deploy:local
```

#### Backend Services
```bash
cd backend
npm install
npm run build
npm run dev
```

#### Frontend Application
```bash
cd frontend
npm install
npm run dev
```

## Development Workflow

### Testing
```bash
# Run all tests
npm run test

# Run tests for specific component
npm run test:contracts
npm run test:backend
npm run test:frontend
```

### Linting
```bash
# Lint all components
npm run lint

# Fix linting issues
npm run lint:fix
```

### Building
```bash
# Build all components
npm run build
```

## Project Structure

```
guardx-defi-platform/
├── contracts/                 # Smart contracts (Hardhat)
│   ├── contracts/
│   │   ├── interfaces/       # Contract interfaces
│   │   ├── CrashGuardCore.sol
│   │   ├── PythPriceMonitor.sol
│   │   └── EmergencyExecutor.sol
│   ├── scripts/              # Deployment scripts
│   └── test/                 # Contract tests
├── backend/                  # Node.js/TypeScript backend
│   ├── src/
│   │   ├── controllers/      # API controllers
│   │   ├── services/         # Business logic services
│   │   ├── middleware/       # Express middleware
│   │   ├── config/          # Configuration files
│   │   └── types/           # TypeScript type definitions
│   └── dist/                # Compiled JavaScript
├── frontend/                 # React/Vite frontend
│   ├── src/
│   │   ├── components/      # React components
│   │   ├── pages/           # Page components
│   │   ├── hooks/           # Custom React hooks
│   │   ├── services/        # API services
│   │   ├── stores/          # State management
│   │   └── utils/           # Utility functions
│   └── dist/                # Built frontend assets
└── docs/                    # Documentation
```

## Key Technologies

- **Smart Contracts**: Solidity, Hardhat 3.0+, OpenZeppelin
- **Backend**: Node.js, TypeScript, Express.js, MongoDB, Redis
- **Frontend**: React, TypeScript, Vite, Tailwind CSS, Wagmi
- **Blockchain**: Ethereum, Pyth Network, Vincent SDK
- **Testing**: Jest, Vitest, Hardhat Test Framework

## Environment Variables

See `.env.example` for all required environment variables. Key variables include:

- `ETHEREUM_RPC_URL`: Ethereum node RPC endpoint
- `MONGODB_URI`: MongoDB connection string
- `JWT_SECRET`: Secret key for JWT token signing
- `PYTH_NETWORK_URL`: Pyth Network API endpoint
- `VINCENT_SDK_API_KEY`: Vincent SDK API key

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support and questions, please open an issue in the GitHub repository or contact the development team.