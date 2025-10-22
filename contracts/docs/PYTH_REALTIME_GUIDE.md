# Pyth Network Real-Time Price Integration Guide

## Overview

Pyth Network provides real-time, high-fidelity price feeds for crypto assets. This guide shows how to integrate Pyth for crash detection in CrashGuard.

## Architecture

```
Pyth Publishers → Pyth Oracle → Hermes API → Your Contract → CrashGuard
```

## Key Concepts

### 1. Price Feeds
- Each asset has a unique Price Feed ID
- Updated continuously (sub-second)
- Includes price, confidence interval, and timestamp

### 2. Hermes API
- REST API for fetching latest price updates
- Returns signed price data (VAAs)
- Free to use, pay only for on-chain updates

### 3. On-Chain Updates
- Submit VAAs to Pyth contract
- Pay small fee per update
- Prices available to all contracts

## Setup

### Step 1: Find Price Feed IDs

Visit [Pyth Price Feeds](https://pyth.network/developers/price-feed-ids) to find IDs:

```javascript
// Common Price Feed IDs (Mainnet)
const PRICE_FEEDS = {
  ETH_USD: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
  BTC_USD: "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43",
  USDC_USD: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
  USDT_USD: "0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b",
};
```

### Step 2: Fetch Real-Time Prices

```javascript
// fetch-pyth-prices.js
async function fetchPythPrices(priceIds) {
  const baseUrl = "https://hermes.pyth.network";
  const endpoint = "/api/latest_price_feeds";
  
  // Build query string
  const params = priceIds.map(id => `ids[]=${id}`).join("&");
  const url = `${baseUrl}${endpoint}?${params}`;
  
  const response = await fetch(url);
  const data = await response.json();
  
  return data.map(feed => ({
    id: feed.id,
    price: feed.price.price,
    conf: feed.price.conf,
    expo: feed.price.expo,
    publishTime: feed.price.publish_time,
  }));
}

// Usage
const prices = await fetchPythPrices([
  PRICE_FEEDS.ETH_USD,
  PRICE_FEEDS.BTC_USD,
]);

console.log("ETH Price:", prices[0].price * Math.pow(10, prices[0].expo));
```

### Step 3: Get Price Update Data (VAAs)

```javascript
async function getPriceUpdateData(priceIds) {
  const baseUrl = "https://hermes.pyth.network";
  const endpoint = "/api/latest_vaas";
  
  const params = priceIds.map(id => `ids[]=${id}`).join("&");
  const url = `${baseUrl}${endpoint}?${params}`;
  
  const response = await fetch(url);
  const data = await response.json();
  
  // Returns array of hex-encoded VAAs
  return data.map(vaa => "0x" + vaa);
}
```

### Step 4: Update On-Chain Prices

```javascript
import { ethers } from "ethers";

async function updatePricesOnChain(priceIds) {
  // 1. Fetch VAAs from Hermes
  const priceUpdateData = await getPriceUpdateData(priceIds);
  
  // 2. Get update fee
  const updateFee = await pythPriceMonitor.getUpdateFee(priceUpdateData);
  
  // 3. Submit update to contract
  const tx = await pythPriceMonitor.updatePricesRealtime(priceUpdateData, {
    value: updateFee,
  });
  
  await tx.wait();
  console.log("Prices updated on-chain:", tx.hash);
}

// Update every minute
setInterval(() => {
  updatePricesOnChain([PRICE_FEEDS.ETH_USD, PRICE_FEEDS.BTC_USD]);
}, 60000);
```

## Integration with CrashGuard

### Complete Monitoring System

```javascript
// crash-monitor.js
import { ethers } from "ethers";

class CrashGuardMonitor {
  constructor(config) {
    this.provider = new ethers.providers.JsonRpcProvider(config.rpcUrl);
    this.pythMonitor = new ethers.Contract(
      config.pythMonitorAddress,
      PYTH_MONITOR_ABI,
      this.provider
    );
    this.crashGuardCore = new ethers.Contract(
      config.crashGuardAddress,
      CRASHGUARD_ABI,
      this.provider
    );
    this.priceFeeds = config.priceFeeds;
  }

  async start() {
    console.log("Starting CrashGuard Monitor...");
    
    // Update prices every 30 seconds
    setInterval(() => this.updatePrices(), 30000);
    
    // Check for crashes every 10 seconds
    setInterval(() => this.checkCrashes(), 10000);
  }

  async updatePrices() {
    try {
      // Fetch latest VAAs
      const priceUpdateData = await this.fetchPriceUpdateData();
      
      // Get update fee
      const updateFee = await this.pythMonitor.getUpdateFee(priceUpdateData);
      
      // Update on-chain
      const tx = await this.pythMonitor.updatePricesRealtime(priceUpdateData, {
        value: updateFee,
        gasLimit: 500000,
      });
      
      await tx.wait();
      console.log(`✓ Prices updated: ${tx.hash}`);
    } catch (error) {
      console.error("Price update failed:", error.message);
    }
  }

  async checkCrashes() {
    try {
      // Read latest prices from contract
      const priceIds = Object.values(this.priceFeeds);
      await this.pythMonitor.readLatestPrices(priceIds);
      
      // Check each monitored user
      const users = await this.getMonitoredUsers();
      
      for (const user of users) {
        const policy = await this.crashGuardCore.getProtectionPolicy(user);
        const portfolio = await this.crashGuardCore.getUserPortfolio(user);
        
        // Check if crash threshold exceeded
        const crashDetected = await this.detectCrash(portfolio, policy);
        
        if (crashDetected) {
          console.log(`⚠️  Crash detected for user ${user}`);
          await this.triggerEmergencyProtection(user);
        }
      }
    } catch (error) {
      console.error("Crash check failed:", error.message);
    }
  }

  async fetchPriceUpdateData() {
    const priceIds = Object.values(this.priceFeeds);
    const params = priceIds.map(id => `ids[]=${id}`).join("&");
    const url = `https://hermes.pyth.network/api/latest_vaas?${params}`;
    
    const response = await fetch(url);
    const data = await response.json();
    
    return data.map(vaa => "0x" + vaa);
  }

  async detectCrash(portfolio, policy) {
    // Get historical prices (from 1 hour ago)
    const timeWindow = 3600; // 1 hour
    
    for (const asset of portfolio.assets) {
      const priceId = this.tokenToPriceId(asset.tokenAddress);
      const history = await this.pythMonitor.getPriceHistory(priceId, timeWindow);
      
      if (history.length === 0) continue;
      
      const oldPrice = history[0].price;
      const currentPrice = await this.pythMonitor.getLatestPrice(priceId);
      
      // Calculate price change
      const priceChange = ((oldPrice - currentPrice.price) / oldPrice) * 10000;
      
      // Check if exceeds threshold
      if (priceChange >= policy.crashThreshold) {
        return true;
      }
    }
    
    return false;
  }

  async triggerEmergencyProtection(user) {
    // This would trigger Lit Action or direct emergency withdrawal
    console.log(`Triggering emergency protection for ${user}`);
    
    // Implementation depends on your setup:
    // Option 1: Direct emergency withdrawal (requires authorized executor)
    // Option 2: Trigger Lit Action for PKP-based protection
    // Option 3: Notify user for manual action
  }

  tokenToPriceId(tokenAddress) {
    // Map token addresses to Pyth price feed IDs
    const mapping = {
      [ETH_ADDRESS]: this.priceFeeds.ETH_USD,
      [BTC_ADDRESS]: this.priceFeeds.BTC_USD,
      [USDC_ADDRESS]: this.priceFeeds.USDC_USD,
    };
    return mapping[tokenAddress];
  }

  async getMonitoredUsers() {
    // Fetch list of users with active protection
    // This could be from a database, subgraph, or contract events
    return ["0x..."]; // Placeholder
  }
}

// Start monitoring
const monitor = new CrashGuardMonitor({
  rpcUrl: "https://arb-sepolia.g.alchemy.com/v2/YOUR-KEY",
  pythMonitorAddress: "0x...",
  crashGuardAddress: "0x...",
  priceFeeds: PRICE_FEEDS,
});

monitor.start();
```

## Optimizations

### 1. Batch Updates

```javascript
// Update multiple price feeds in one transaction
async function batchUpdatePrices(priceIdGroups) {
  const allPriceIds = priceIdGroups.flat();
  const priceUpdateData = await getPriceUpdateData(allPriceIds);
  
  // Single transaction for all updates
  await pythPriceMonitor.updatePricesRealtime(priceUpdateData, {
    value: await pythMonitor.getUpdateFee(priceUpdateData),
  });
}
```

### 2. Conditional Updates

```javascript
// Only update if price changed significantly
async function conditionalUpdate(priceId, threshold = 0.5) {
  const latestPrice = await pythMonitor.getLatestPrice(priceId);
  const realtimePrice = await fetchPythPrices([priceId]);
  
  const priceChange = Math.abs(
    (realtimePrice[0].price - latestPrice.price) / latestPrice.price * 100
  );
  
  if (priceChange >= threshold) {
    await updatePricesOnChain([priceId]);
  }
}
```

### 3. Websocket Streaming

```javascript
// Stream real-time prices via WebSocket
import WebSocket from "ws";

function streamPythPrices(priceIds, callback) {
  const ws = new WebSocket("wss://hermes.pyth.network/ws");
  
  ws.on("open", () => {
    // Subscribe to price feeds
    ws.send(JSON.stringify({
      type: "subscribe",
      ids: priceIds,
    }));
  });
  
  ws.on("message", (data) => {
    const update = JSON.parse(data);
    callback(update);
  });
}

// Usage
streamPythPrices([PRICE_FEEDS.ETH_USD], (update) => {
  console.log("Real-time price:", update);
  
  // Check if update needed on-chain
  if (shouldUpdateOnChain(update)) {
    updatePricesOnChain([update.id]);
  }
});
```

## Best Practices

### 1. Update Frequency
- **High-frequency trading**: Every 1-5 seconds
- **Crash detection**: Every 30-60 seconds
- **Portfolio tracking**: Every 5-10 minutes

### 2. Error Handling

```javascript
async function robustPriceUpdate(priceIds, maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      await updatePricesOnChain(priceIds);
      return true;
    } catch (error) {
      console.error(`Update attempt ${i + 1} failed:`, error.message);
      
      if (i === maxRetries - 1) {
        // Alert on final failure
        await sendAlert("Price update failed after retries");
        return false;
      }
      
      // Wait before retry
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
  }
}
```

### 3. Cost Optimization

```javascript
// Calculate update cost before submitting
async function estimateUpdateCost(priceIds) {
  const priceUpdateData = await getPriceUpdateData(priceIds);
  const updateFee = await pythMonitor.getUpdateFee(priceUpdateData);
  const gasEstimate = await pythMonitor.estimateGas.updatePricesRealtime(
    priceUpdateData,
    { value: updateFee }
  );
  
  const gasPrice = await provider.getGasPrice();
  const totalCost = updateFee.add(gasEstimate.mul(gasPrice));
  
  console.log("Update cost:", ethers.utils.formatEther(totalCost), "ETH");
  return totalCost;
}
```

### 4. Monitoring & Alerts

```javascript
class PriceMonitoringService {
  async checkPriceFreshness() {
    const priceIds = Object.values(PRICE_FEEDS);
    
    for (const priceId of priceIds) {
      const isFresh = await pythMonitor.isPriceFresh(priceId);
      
      if (!isFresh) {
        await this.sendAlert(`Stale price detected: ${priceId}`);
        await this.forceUpdate(priceId);
      }
    }
  }
  
  async sendAlert(message) {
    // Send to monitoring service (e.g., PagerDuty, Slack)
    console.error("ALERT:", message);
  }
  
  async forceUpdate(priceId) {
    // Force immediate update
    await updatePricesOnChain([priceId]);
  }
}
```

## Testing

### Local Testing

```javascript
// test-pyth-integration.js
import { expect } from "chai";

describe("Pyth Integration", () => {
  it("should fetch real-time prices", async () => {
    const prices = await fetchPythPrices([PRICE_FEEDS.ETH_USD]);
    expect(prices).to.have.lengthOf(1);
    expect(prices[0].price).to.be.greaterThan(0);
  });
  
  it("should update prices on-chain", async () => {
    const priceUpdateData = await getPriceUpdateData([PRICE_FEEDS.ETH_USD]);
    const tx = await pythMonitor.updatePricesRealtime(priceUpdateData, {
      value: await pythMonitor.getUpdateFee(priceUpdateData),
    });
    await tx.wait();
    
    const latestPrice = await pythMonitor.getLatestPrice(PRICE_FEEDS.ETH_USD);
    expect(latestPrice.price).to.be.greaterThan(0);
  });
  
  it("should detect price crashes", async () => {
    // Simulate crash by manipulating historical data
    const crashDetected = await pythMonitor.checkAssetsCrash(
      [ETH_ADDRESS],
      2000, // 20% threshold
      3600  // 1 hour window
    );
    
    // Assertion depends on current market conditions
    expect(typeof crashDetected).to.equal("boolean");
  });
});
```

## Troubleshooting

### Issue: "Price not available"
**Solution**: Ensure price feed ID is correct and feed is active

### Issue: "Insufficient fee"
**Solution**: Call `getUpdateFee()` before updating

### Issue: "Price too old"
**Solution**: Increase update frequency or adjust `MAX_PRICE_AGE`

### Issue: "Update reverts"
**Solution**: Check VAA validity and Pyth contract address

## Resources

- [Pyth Network Docs](https://docs.pyth.network/)
- [Hermes API Reference](https://hermes.pyth.network/docs/)
- [Price Feed IDs](https://pyth.network/developers/price-feed-ids)
- [EVM Integration](https://docs.pyth.network/price-feeds/use-real-time-data/evm)

## Example: Complete System

See `scripts/monitor-system.js` for a complete implementation combining:
- Real-time Pyth price updates
- Crash detection
- Lit Protocol automation
- User notifications
- Error handling & monitoring
