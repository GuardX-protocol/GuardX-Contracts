# Lit Protocol Integration Guide

## Overview

Lit Protocol enables decentralized access control and programmable signing for your CrashGuard system. It uses Programmable Key Pairs (PKPs) to automate emergency protection actions based on market conditions.

## Key Concepts

### 1. PKP (Programmable Key Pair)
- A decentralized wallet controlled by Lit Actions (JavaScript code)
- Can sign transactions automatically based on conditions
- No single entity controls the private key

### 2. Lit Actions
- JavaScript code that runs on Lit Network nodes
- Can fetch data, make decisions, and sign transactions
- Executed when specific conditions are met

### 3. Access Control Conditions
- Define who can decrypt data or execute actions
- Based on on-chain state (token balance, NFT ownership, etc.)

## How CrashGuard Uses Lit Protocol

### Automated Emergency Protection

```
Market Crash Detected → Lit Action Triggered → PKP Signs Transaction → Assets Protected
```

## Setup Guide

### Step 1: Create a PKP

```javascript
import * as LitJsSdk from "@lit-protocol/lit-node-client";

const litNodeClient = new LitJsSdk.LitNodeClient({
  litNetwork: "cayenne", // or "habanero" for testnet
});

await litNodeClient.connect();

// Mint a PKP
const pkp = await litNodeClient.mintPKP({
  authMethod: {
    authMethodType: 1, // WebAuthn
    accessToken: "your-auth-token",
  },
});

console.log("PKP Address:", pkp.tokenId);
console.log("PKP Public Key:", pkp.publicKey);
```

### Step 2: Create a Lit Action for Emergency Protection

```javascript
// lit-action-emergency-protect.js
const go = async () => {
  // Fetch price data from Pyth
  const priceResponse = await Lit.Actions.runOnce(
    { waitForResponse: true, name: "fetchPrice" },
    async () => {
      const response = await fetch(
        "https://hermes.pyth.network/api/latest_price_feeds?ids[]=" + priceId
      );
      return response.json();
    }
  );

  const currentPrice = priceResponse.price;
  const priceChange = ((historicalPrice - currentPrice) / historicalPrice) * 100;

  // Check if crash threshold exceeded
  if (priceChange >= crashThreshold) {
    // Sign transaction to trigger emergency withdrawal
    const sigShare = await Lit.Actions.signEcdsa({
      toSign: ethers.utils.arrayify(transactionHash),
      publicKey: pkpPublicKey,
      sigName: "emergencyProtection",
    });

    Lit.Actions.setResponse({ response: JSON.stringify({ signed: true, sigShare }) });
  } else {
    Lit.Actions.setResponse({ response: JSON.stringify({ signed: false }) });
  }
};

go();
```

### Step 3: Register PKP with CrashGuard Contract

```javascript
import { ethers } from "ethers";

const crashGuardCore = new ethers.Contract(
  CRASHGUARD_ADDRESS,
  CRASHGUARD_ABI,
  signer
);

// Setup PKP authorization
await crashGuardCore.setupPKPAuthorization(
  userAddress,
  pkpAddress,
  litActionId // IPFS hash of your Lit Action
);
```

### Step 4: Execute Lit Action for Monitoring

```javascript
import * as LitJsSdk from "@lit-protocol/lit-node-client";

const litNodeClient = new LitJsSdk.LitNodeClient({
  litNetwork: "cayenne",
});

await litNodeClient.connect();

// Execute Lit Action
const result = await litNodeClient.executeJs({
  code: litActionCode, // Your Lit Action code
  authSig: await LitJsSdk.checkAndSignAuthMessage({ chain: "ethereum" }),
  jsParams: {
    priceId: "0x...", // Pyth price feed ID
    crashThreshold: 20, // 20% drop
    historicalPrice: 2000,
    pkpPublicKey: pkpPublicKey,
    transactionHash: txHash,
  },
});

console.log("Lit Action Result:", result);
```

## Real-World Usage Flow

### 1. User Setup (One-time)

```javascript
// 1. User creates PKP
const pkp = await createPKP();

// 2. User sets protection policy
await crashGuardCore.setProtectionPolicy({
  crashThreshold: 2000, // 20% (basis points)
  maxSlippage: 500, // 5%
  stablecoinPreference: USDC_ADDRESS,
  gasLimit: 500000,
});

// 3. User authorizes PKP
await crashGuardCore.setupPKPAuthorization(
  userAddress,
  pkp.address,
  litActionIPFSHash
);

// 4. User deposits assets
await crashGuardCore.depositAsset(ETH_ADDRESS, ethers.utils.parseEther("1"), {
  value: ethers.utils.parseEther("1"),
});
```

### 2. Automated Monitoring (Continuous)

```javascript
// Run this in a cron job or serverless function
setInterval(async () => {
  // Fetch latest prices
  const prices = await fetchPythPrices();

  // Execute Lit Action to check conditions
  const result = await litNodeClient.executeJs({
    code: emergencyProtectionLitAction,
    jsParams: {
      userAddress,
      currentPrices: prices,
      crashThreshold: userPolicy.crashThreshold,
    },
  });

  if (result.response.signed) {
    // Lit Action detected crash and signed transaction
    // Submit transaction to blockchain
    await submitEmergencyTransaction(result.response.sigShare);
  }
}, 60000); // Check every minute
```

### 3. Emergency Protection (Automatic)

When crash detected:
1. Lit Action verifies crash conditions
2. PKP signs emergency withdrawal transaction
3. Transaction submitted to CrashGuardCore
4. Assets converted to stablecoin
5. User notified

## Best Practices

### Security

1. **Store Lit Actions on IPFS**: Immutable and verifiable
2. **Use Access Control Conditions**: Restrict who can execute actions
3. **Test on Testnet First**: Use Cayenne or Habanero networks
4. **Implement Rate Limiting**: Prevent spam execution
5. **Verify Signatures**: Always validate PKP signatures on-chain

### Performance

1. **Cache Price Data**: Don't fetch on every execution
2. **Batch Operations**: Group multiple checks together
3. **Use Webhooks**: Trigger actions based on events
4. **Optimize Gas**: Minimize on-chain operations

### Monitoring

1. **Log All Executions**: Track Lit Action runs
2. **Alert on Failures**: Monitor for execution errors
3. **Track Gas Costs**: Optimize for efficiency
4. **Audit Regularly**: Review Lit Action code

## Example: Complete Integration

```javascript
// complete-integration.js
import * as LitJsSdk from "@lit-protocol/lit-node-client";
import { ethers } from "ethers";

class CrashGuardLitIntegration {
  constructor(config) {
    this.litNodeClient = new LitJsSdk.LitNodeClient({
      litNetwork: config.network,
    });
    this.provider = new ethers.providers.JsonRpcProvider(config.rpcUrl);
    this.crashGuardCore = new ethers.Contract(
      config.crashGuardAddress,
      config.abi,
      this.provider
    );
  }

  async initialize() {
    await this.litNodeClient.connect();
  }

  async setupUserProtection(userAddress, pkpInfo) {
    // 1. Register PKP with contract
    const tx = await this.crashGuardCore.setupPKPAuthorization(
      userAddress,
      pkpInfo.address,
      pkpInfo.litActionId
    );
    await tx.wait();

    // 2. Store user configuration
    await this.storeUserConfig(userAddress, pkpInfo);

    return { success: true, txHash: tx.hash };
  }

  async monitorAndProtect(userAddress) {
    // Fetch user policy
    const policy = await this.crashGuardCore.getProtectionPolicy(userAddress);

    // Fetch current prices
    const prices = await this.fetchPrices();

    // Execute Lit Action
    const result = await this.litNodeClient.executeJs({
      code: this.getLitActionCode(),
      jsParams: {
        userAddress,
        policy,
        prices,
      },
    });

    if (result.response.emergencyTriggered) {
      await this.executeEmergencyProtection(userAddress, result.response);
    }

    return result;
  }

  getLitActionCode() {
    return `
      const go = async () => {
        // Check crash conditions
        const crashDetected = checkCrashConditions(prices, policy);
        
        if (crashDetected) {
          // Sign emergency transaction
          const sigShare = await Lit.Actions.signEcdsa({
            toSign: ethers.utils.arrayify(txHash),
            publicKey: pkpPublicKey,
            sigName: "emergency",
          });
          
          Lit.Actions.setResponse({
            response: JSON.stringify({
              emergencyTriggered: true,
              sigShare,
            }),
          });
        } else {
          Lit.Actions.setResponse({
            response: JSON.stringify({ emergencyTriggered: false }),
          });
        }
      };
      go();
    `;
  }

  async fetchPrices() {
    // Fetch from Pyth Hermes API
    const response = await fetch(
      "https://hermes.pyth.network/api/latest_price_feeds?ids[]=" + priceIds.join("&ids[]=")
    );
    return response.json();
  }

  async executeEmergencyProtection(userAddress, litResponse) {
    // Reconstruct full signature from sig shares
    const signature = await this.reconstructSignature(litResponse.sigShare);

    // Submit emergency transaction
    const tx = await this.crashGuardCore.pkpWithdrawAsset(
      userAddress,
      tokenAddress,
      amount,
      litActionId,
      { signature }
    );

    await tx.wait();
    console.log("Emergency protection executed:", tx.hash);
  }
}

// Usage
const integration = new CrashGuardLitIntegration({
  network: "cayenne",
  rpcUrl: "https://arb-sepolia.g.alchemy.com/v2/YOUR-KEY",
  crashGuardAddress: "0x...",
  abi: CRASHGUARD_ABI,
});

await integration.initialize();
await integration.setupUserProtection(userAddress, pkpInfo);

// Monitor continuously
setInterval(() => {
  integration.monitorAndProtect(userAddress);
}, 60000);
```

## Troubleshooting

### Common Issues

1. **PKP Not Authorized**
   - Ensure `setupPKPAuthorization` was called
   - Check PKP is registered with Lit Relay Contract

2. **Lit Action Fails**
   - Verify JavaScript syntax
   - Check all required parameters are passed
   - Test in Lit Protocol playground first

3. **Signature Invalid**
   - Ensure correct PKP public key
   - Verify transaction hash format
   - Check signature reconstruction

4. **Gas Estimation Fails**
   - Increase gas limit in policy
   - Check contract has sufficient balance
   - Verify all conditions are met

## Resources

- [Lit Protocol Docs](https://developer.litprotocol.com/)
- [Lit Actions Examples](https://github.com/LIT-Protocol/js-sdk/tree/master/packages/lit-node-client/src/lib/lit-actions)
- [PKP Minting Guide](https://developer.litprotocol.com/v3/sdk/wallets/minting)
- [Access Control Conditions](https://developer.litprotocol.com/v3/sdk/access-control/evm/basic-examples)

## Support

For issues or questions:
- GitHub Issues: [Your Repo]
- Discord: [Lit Protocol Discord]
- Documentation: [Your Docs]
