# Frontend Integration Guide

## Contract Addresses (Arbitrum Sepolia)

```javascript
const CONTRACTS = {
  // Core Contracts
  CrashGuardCore: "0xecC8AaF4f40D47576Da9931e554e6F7df53c41CC",
  PythPriceMonitor: "0x5AF0F97612B3F6cf35F94274C4FD89BA363DDa4f",
  SimpleCrossChainBridge: "0x1D568B2a2f67Edb788DA111D153319001378Ee32",
  
  // Supporting Contracts
  EmergencyExecutor: "0x41Bd52f4102634c7fe62a20957206A18e03Df76A",
  LitProtocolIntegration: "0x0Bc70cB52Ea957fA6927B5D335D8CF97967e6750",
  
  // Network Info
  chainId: 421614,
  rpcUrl: "https://sepolia-rollup.arbitrum.io/rpc"
};
```

## Quick Setup

### 1. Install Dependencies

```bash
npm install ethers @lit-protocol/lit-node-client
```

### 2. Basic Contract Setup

```javascript
import { ethers } from "ethers";

// Connect to Arbitrum Sepolia
const provider = new ethers.JsonRpcProvider(CONTRACTS.rpcUrl);
const signer = new ethers.Wallet(privateKey, provider);

// Contract instances
const crashGuard = new ethers.Contract(
  CONTRACTS.CrashGuardCore,
  CRASHGUARD_ABI,
  signer
);

const bridge = new ethers.Contract(
  CONTRACTS.SimpleCrossChainBridge,
  BRIDGE_ABI,
  signer
);
```

## Core Features

### 🏦 Deposit Assets (Permissionless)

```javascript
// Deposit any token (no admin approval needed!)
async function depositToken(tokenAddress, amount) {
  // For stablecoins: minimum 1 token (1e6 for USDC)
  // For other tokens: minimum 0.01 tokens (1e16 for ETH)
  
  if (tokenAddress === ethers.ZeroAddress) {
    // ETH deposit
    await crashGuard.depositAsset(tokenAddress, amount, {
      value: amount
    });
  } else {
    // ERC20 deposit (approve first)
    const token = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
    await token.approve(CONTRACTS.CrashGuardCore, amount);
    await crashGuard.depositAsset(tokenAddress, amount);
  }
}

// Usage
await depositToken(ethers.ZeroAddress, ethers.parseEther("0.01")); // ETH
await depositToken(USDC_ADDRESS, 1_000_000); // 1 USDC
```

### ⚙️ Set Protection Policy (Client Configurable)

```javascript
async function setProtection(crashThreshold, maxSlippage, stablecoin) {
  await crashGuard.setProtectionPolicy({
    crashThreshold: crashThreshold, // 2000 = 20%
    maxSlippage: maxSlippage,       // 500 = 5%
    emergencyActions: [],
    stablecoinPreference: stablecoin,
    gasLimit: 500000
  });
}

// Usage
await setProtection(2000, 500, USDC_ADDRESS); // 20% crash, 5% slippage
```

### 🌉 Cross-Chain Deposits

```javascript
async function crossChainDeposit(token, amount, destinationChain, destinationUser) {
  await bridge.initiateCrossChainDeposit(
    token,
    amount,
    destinationChain, // 1 = Ethereum, 42161 = Arbitrum
    destinationUser,
    { value: token === ethers.ZeroAddress ? amount : 0 }
  );
}

// Usage
await crossChainDeposit(
  ethers.ZeroAddress,
  ethers.parseEther("0.1"),
  1, // Ethereum mainnet
  userAddress
);
```

### 📊 Get User Data

```javascript
// Get user portfolio
async function getUserPortfolio(userAddress) {
  return await crashGuard.getUserPortfolio(userAddress);
}

// Get user balance
async function getUserBalance(userAddress, tokenAddress) {
  return await crashGuard.getUserBalance(userAddress, tokenAddress);
}

// Get protection policy
async function getProtectionPolicy(userAddress) {
  return await crashGuard.getProtectionPolicy(userAddress);
}

// Check if token is supported
async function isTokenSupported(tokenAddress) {
  return await crashGuard.isTokenSupported(tokenAddress);
}
```

### 💰 Withdraw Assets

```javascript
async function withdrawAsset(tokenAddress, amount) {
  await crashGuard.withdrawAsset(tokenAddress, amount);
}
```

## UI Components

### Deposit Form

```javascript
function DepositForm() {
  const [token, setToken] = useState(ethers.ZeroAddress);
  const [amount, setAmount] = useState("");
  
  const handleDeposit = async () => {
    const parsedAmount = token === ethers.ZeroAddress 
      ? ethers.parseEther(amount)
      : ethers.parseUnits(amount, 6); // Assuming USDC
      
    await depositToken(token, parsedAmount);
  };
  
  return (
    <form onSubmit={handleDeposit}>
      <select value={token} onChange={(e) => setToken(e.target.value)}>
        <option value={ethers.ZeroAddress}>ETH</option>
        <option value={USDC_ADDRESS}>USDC</option>
      </select>
      <input 
        type="number" 
        value={amount} 
        onChange={(e) => setAmount(e.target.value)}
        placeholder={token === ethers.ZeroAddress ? "Min: 0.01 ETH" : "Min: 1 USDC"}
      />
      <button type="submit">Deposit</button>
    </form>
  );
}
```

### Protection Settings

```javascript
function ProtectionSettings() {
  const [crashThreshold, setCrashThreshold] = useState(2000); // 20%
  const [maxSlippage, setMaxSlippage] = useState(500); // 5%
  
  const handleSave = async () => {
    await setProtection(crashThreshold, maxSlippage, USDC_ADDRESS);
  };
  
  return (
    <div>
      <label>
        Crash Threshold: {crashThreshold / 100}%
        <input 
          type="range" 
          min="100" 
          max="5000" 
          value={crashThreshold}
          onChange={(e) => setCrashThreshold(e.target.value)}
        />
      </label>
      
      <label>
        Max Slippage: {maxSlippage / 100}%
        <input 
          type="range" 
          min="50" 
          max="1000" 
          value={maxSlippage}
          onChange={(e) => setMaxSlippage(e.target.value)}
        />
      </label>
      
      <button onClick={handleSave}>Save Settings</button>
    </div>
  );
}
```

### Portfolio Display

```javascript
function Portfolio({ userAddress }) {
  const [portfolio, setPortfolio] = useState(null);
  
  useEffect(() => {
    async function loadPortfolio() {
      const data = await getUserPortfolio(userAddress);
      setPortfolio(data);
    }
    loadPortfolio();
  }, [userAddress]);
  
  return (
    <div>
      <h3>Your Portfolio</h3>
      {portfolio?.assets.map((asset, i) => (
        <div key={i}>
          <span>Token: {asset.tokenAddress}</span>
          <span>Amount: {ethers.formatUnits(asset.amount, 18)}</span>
          <span>Value: ${asset.valueUSD}</span>
        </div>
      ))}
      <p>Total Value: ${portfolio?.totalValue}</p>
    </div>
  );
}
```

## Event Listening

```javascript
// Listen for deposits
crashGuard.on("AssetDeposited", (user, token, amount) => {
  console.log(`${user} deposited ${amount} of ${token}`);
});

// Listen for emergency triggers
crashGuard.on("EmergencyProtectionTriggered", (user, timestamp) => {
  console.log(`Emergency protection triggered for ${user}`);
});

// Listen for cross-chain deposits
bridge.on("CrossChainDepositInitiated", (user, token, amount, chain, hash) => {
  console.log(`Cross-chain deposit initiated: ${hash}`);
});
```

## Error Handling

```javascript
async function safeContractCall(contractFunction) {
  try {
    const tx = await contractFunction();
    await tx.wait();
    return { success: true, tx };
  } catch (error) {
    if (error.reason) {
      // Custom error from contract
      return { success: false, error: error.reason };
    }
    return { success: false, error: "Transaction failed" };
  }
}

// Usage
const result = await safeContractCall(() => 
  crashGuard.depositAsset(token, amount, { value })
);

if (!result.success) {
  alert(`Error: ${result.error}`);
}
```

## Token Addresses (Arbitrum Sepolia)

```javascript
const TOKENS = {
  USDC: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
  USDT: "0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0",
  WETH: "0x980B62Da83eFf3D4576C647993b0c1D7faf17c73"
};
```

## Key Features for Frontend

1. **Permissionless Deposits** - Any token can be deposited without admin approval
2. **Client Configuration** - Users set their own crash thresholds and slippage
3. **Cross-Chain Support** - Bridge assets from other chains
4. **Real-Time Monitoring** - Prices updated every 30-60 seconds
5. **Automated Protection** - Lit Protocol PKPs handle emergency actions

## Next Steps

1. Build deposit/withdraw interface
2. Add protection policy configuration
3. Implement portfolio dashboard
4. Add cross-chain bridge UI
5. Set up real-time price monitoring
6. Integrate Lit Protocol for automation

## Support

- Contract ABIs: Available in `contracts/artifacts/`
- Network: Arbitrum Sepolia (Chain ID: 421614)
- Block Explorer: https://sepolia.arbiscan.io/