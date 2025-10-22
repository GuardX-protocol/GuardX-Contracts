import { network } from "hardhat";
import dotenv from "dotenv";

dotenv.config();

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

// Deployed contract addresses
const CRASHGUARD_CORE = "0x9Fea1F8834BE8814182d89974Eb6bb7C6c09CEcB";
const PYTH_MONITOR = "0x563a696034faE451F3095C229A074cfA42E4C116";

// Token addresses on Arbitrum Sepolia
const USDC_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
const USDT_ADDRESS = "0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0";
const WETH_ADDRESS = "0x980B62Da83eFf3D4576C647993b0c1D7faf17c73";

// Pyth Price Feed IDs
const PRICE_FEEDS = {
    ETH_USD: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
    BTC_USD: "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43",
    USDC_USD: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
    USDT_USD: "0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b",
};

async function main() {
    console.log("\n🔧 Configuring CrashGuard Deployment...\n");
    const connection: any = await network.connect();
    const { ethers } = connection;

    const [deployer] = await ethers.getSigners();
    console.log("Configuring with:", deployer.address);

    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("Balance:", ethers.formatEther(balance), "ETH\n");

    // Get contract instances
    const crashGuardCore = await ethers.getContractAt("CrashGuardCore", CRASHGUARD_CORE);

    // Use the interface for PythMonitor
    const pythMonitorAbi = [
        "function addPriceFeed(bytes32 priceId, address tokenAddress) external",
        "function tokenToPriceId(address token) external view returns (bytes32)",
    ];
    const pythMonitor = new ethers.Contract(PYTH_MONITOR, pythMonitorAbi, deployer);

    console.log("=== STEP 1: Configure Stablecoins ===\n");

    try {
        console.log("Adding USDC as stablecoin...");
        const tx1 = await crashGuardCore.addSupportedToken(USDC_ADDRESS, true);
        await tx1.wait();
        console.log("✓ USDC configured");
        await sleep(2000);
    } catch (error: any) {
        console.log("⚠️  USDC already configured or error:", error.message);
    }

    try {
        console.log("Adding USDT as stablecoin...");
        const tx2 = await crashGuardCore.addSupportedToken(USDT_ADDRESS, true);
        await tx2.wait();
        console.log("✓ USDT configured");
        await sleep(2000);
    } catch (error: any) {
        console.log("⚠️  USDT already configured or error:", error.message);
    }

    try {
        console.log("Adding WETH as regular token...");
        const tx3 = await crashGuardCore.addSupportedToken(WETH_ADDRESS, false);
        await tx3.wait();
        console.log("✓ WETH configured");
        await sleep(2000);
    } catch (error: any) {
        console.log("⚠️  WETH already configured or error:", error.message);
    }

    console.log("\n=== STEP 2: Configure Pyth Price Feeds ===\n");

    try {
        console.log("Adding ETH/USD price feed...");
        const tx4 = await pythMonitor.addPriceFeed(PRICE_FEEDS.ETH_USD, WETH_ADDRESS);
        await tx4.wait();
        console.log("✓ ETH/USD price feed added");
        await sleep(2000);
    } catch (error: any) {
        console.log("⚠️  ETH/USD already configured or error:", error.message);
    }

    try {
        console.log("Adding USDC/USD price feed...");
        const tx5 = await pythMonitor.addPriceFeed(PRICE_FEEDS.USDC_USD, USDC_ADDRESS);
        await tx5.wait();
        console.log("✓ USDC/USD price feed added");
        await sleep(2000);
    } catch (error: any) {
        console.log("⚠️  USDC/USD already configured or error:", error.message);
    }

    try {
        console.log("Adding USDT/USD price feed...");
        const tx6 = await pythMonitor.addPriceFeed(PRICE_FEEDS.USDT_USD, USDT_ADDRESS);
        await tx6.wait();
        console.log("✓ USDT/USD price feed added");
        await sleep(2000);
    } catch (error: any) {
        console.log("⚠️  USDT/USD already configured or error:", error.message);
    }

    console.log("\n=== STEP 3: Verify Configuration ===\n");

    // Check stablecoin status
    const isUSDCStablecoin = await crashGuardCore.isStablecoin(USDC_ADDRESS);
    const isUSDTStablecoin = await crashGuardCore.isStablecoin(USDT_ADDRESS);
    const isWETHStablecoin = await crashGuardCore.isStablecoin(WETH_ADDRESS);

    console.log("Stablecoin Status:");
    console.log(`  USDC: ${isUSDCStablecoin ? "✓ Stablecoin" : "✗ Not stablecoin"}`);
    console.log(`  USDT: ${isUSDTStablecoin ? "✓ Stablecoin" : "✗ Not stablecoin"}`);
    console.log(`  WETH: ${isWETHStablecoin ? "✗ Not stablecoin" : "✓ Regular token"}`);

    // Check price feed mappings
    const ethPriceId = await pythMonitor.tokenToPriceId(WETH_ADDRESS);
    const usdcPriceId = await pythMonitor.tokenToPriceId(USDC_ADDRESS);
    const usdtPriceId = await pythMonitor.tokenToPriceId(USDT_ADDRESS);

    console.log("\nPrice Feed Mappings:");
    console.log(`  WETH: ${ethPriceId !== ethers.ZeroHash ? "✓ Configured" : "✗ Not configured"}`);
    console.log(`  USDC: ${usdcPriceId !== ethers.ZeroHash ? "✓ Configured" : "✗ Not configured"}`);
    console.log(`  USDT: ${usdtPriceId !== ethers.ZeroHash ? "✓ Configured" : "✗ Not configured"}`);

    console.log("\n=== Configuration Summary ===\n");
    console.log("✅ Stablecoins configured:");
    console.log(`   - USDC: ${USDC_ADDRESS}`);
    console.log(`   - USDT: ${USDT_ADDRESS}`);
    console.log("\n✅ Regular tokens configured:");
    console.log(`   - WETH: ${WETH_ADDRESS}`);
    console.log("\n✅ Price feeds configured:");
    console.log(`   - ETH/USD: ${PRICE_FEEDS.ETH_USD}`);
    console.log(`   - USDC/USD: ${PRICE_FEEDS.USDC_USD}`);
    console.log(`   - USDT/USD: ${PRICE_FEEDS.USDT_USD}`);

    console.log("\n=== Next Steps ===\n");
    console.log("1. Start monitoring system:");
    console.log("   node scripts/monitor-system.js\n");
    console.log("2. Test user deposit:");
    console.log("   npx hardhat run scripts/test-deposit.ts --network arbitrumSepolia\n");
    console.log("3. Update prices:");
    console.log("   npx hardhat run scripts/updatePythPrices.ts --network arbitrumSepolia\n");

    console.log("✅ Configuration complete!\n");
}

main().catch((error) => {
    console.error("\n❌ Configuration failed:", error);
    process.exitCode = 1;
});
