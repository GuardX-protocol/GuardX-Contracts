import { network } from "hardhat";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import CrashGuardSystemModule from "../ignition/modules/CrashGuardSystem.js";

dotenv.config();

async function main() {
    console.log("\n🚀 Starting deployment with Hardhat Ignition...\n");

    try {
        // Connect to network and get ignition instance
        const connection: any = await network.connect();
        const { ignition, provider } = connection;

        // Deploy using Ignition with parameters
        const parameters = {
            pythPriceFeedAddress: process.env.PYTH_PRICE_FEED_ADDRESS || "0x4305FB66699C3B2702D4d05CF36551390A4c69C6"
        };

        const deployment = await ignition.deploy(CrashGuardSystemModule, { parameters });

        console.log("\n✅ All contracts deployed and configured!\n");

        // Extract deployed contracts
        const {
            pythPriceMonitor,
            dexAggregator,
            crashGuardCore,
            emergencyExecutor,
            litRelayContract,
            litProtocolIntegration,
            crossChainManager,
            crossChainEmergencyCoordinator
        } = deployment;

        // Add supported tokens if configured (optional for production)
        if (process.env.USDC_ADDRESS && process.env.USDT_ADDRESS && process.env.DAI_ADDRESS) {
            console.log("📝 Adding supported tokens...");
            const supportedTokens = [
                process.env.USDC_ADDRESS,
                process.env.USDT_ADDRESS,
                process.env.DAI_ADDRESS
            ];
            for (const token of supportedTokens) {
                await crashGuardCore.addSupportedToken(token);
            }
            console.log("✓ Added supported tokens\n");
        }

        // Get addresses
        const addresses = {
            PythPriceMonitor: await pythPriceMonitor.getAddress(),
            DEXAggregator: await dexAggregator.getAddress(),
            CrashGuardCore: await crashGuardCore.getAddress(),
            EmergencyExecutor: await emergencyExecutor.getAddress(),
            LitRelayContract: await litRelayContract.getAddress(),
            LitProtocolIntegration: await litProtocolIntegration.getAddress(),
            CrossChainManager: await crossChainManager.getAddress(),
            CrossChainEmergencyCoordinator: await crossChainEmergencyCoordinator.getAddress()
        };

        // Summary
        console.log("=== DEPLOYMENT SUMMARY ===");
        Object.entries(addresses).forEach(([name, address]) => {
            console.log(`${name}: ${address}`);
        });

        // Save deployment info
        const deploymentsDir = path.join(process.cwd(), 'deployments');
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }

        // Get network info
        const networkName = (network as any).name || 'hardhat';

        const deploymentInfo = {
            network: networkName,
            timestamp: new Date().toISOString(),
            contracts: addresses
        };

        const filename = `deployment-${networkName}-${Date.now()}.json`;
        fs.writeFileSync(
            path.join(deploymentsDir, filename),
            JSON.stringify(deploymentInfo, null, 2)
        );
        console.log(`\n💾 Saved to: deployments/${filename}`);

    } catch (error) {
        console.error("\n❌ Deployment failed:", error);
        process.exit(1);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
