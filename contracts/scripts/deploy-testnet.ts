import { network } from "hardhat";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import TestnetDeploymentModule from "../ignition/modules/TestnetDeployment.js";

dotenv.config();

async function main() {
    console.log("\n🚀 Starting testnet deployment with Hardhat Ignition...\n");

    try {
        // Connect to network and get ignition instance
        const connection: any = await network.connect();
        const { ignition, provider } = connection;

        // Get network info
        const networkName = (network as any).name || 'hardhat';

        console.log("Network:", networkName);

        // Set Pyth address based on network name
        const pythAddress = networkName === 'sepolia' ?
            "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21" : // Sepolia
            "0x4305FB66699C3B2702D4d05CF36551390A4c69C6";   // Default

        // Deploy using Ignition with parameters
        const parameters = {
            pythPriceFeedAddress: pythAddress
        };

        const deployment = await ignition.deploy(TestnetDeploymentModule, { parameters });

        console.log("\n✅ All contracts deployed and configured!\n");

        // Extract deployed contracts
        const {
            mockUSDC,
            mockUSDT,
            mockDAI,
            pythPriceMonitor,
            dexAggregator,
            crashGuardCore,
            emergencyExecutor,
            litRelayContract,
            litProtocolIntegration,
            crossChainManager,
            crossChainEmergencyCoordinator
        } = deployment;

        // Mint test tokens to deployer
        console.log("📝 Minting test tokens...");
        const testAmount = 10000n * 10n ** 18n; // 10,000 tokens
        await mockUSDC.mint((await provider.getSigner()).address, testAmount / 10n ** 12n); // 6 decimals
        await mockUSDT.mint((await provider.getSigner()).address, testAmount / 10n ** 12n); // 6 decimals
        await mockDAI.mint((await provider.getSigner()).address, testAmount); // 18 decimals
        console.log("✓ Minted test tokens\n");

        // Get addresses
        const mockTokenAddresses = {
            USDC: await mockUSDC.getAddress(),
            USDT: await mockUSDT.getAddress(),
            DAI: await mockDAI.getAddress()
        };

        const contractAddresses = {
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
        console.log("=== TESTNET DEPLOYMENT SUMMARY ===");
        console.log("\nMock Tokens:");
        Object.entries(mockTokenAddresses).forEach(([name, address]) => {
            console.log(`${name}: ${address}`);
        });
        console.log("\nCore Contracts:");
        Object.entries(contractAddresses).forEach(([name, address]) => {
            console.log(`${name}: ${address}`);
        });

        // Save deployment info
        const deploymentsDir = path.join(process.cwd(), 'deployments');
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }

        const deploymentInfo = {
            network: networkName,
            timestamp: new Date().toISOString(),
            mockTokens: mockTokenAddresses,
            contracts: contractAddresses
        };

        const filename = `testnet-deployment-${networkName}-${Date.now()}.json`;
        fs.writeFileSync(
            path.join(deploymentsDir, filename),
            JSON.stringify(deploymentInfo, null, 2)
        );
        console.log(`\n💾 Saved to: deployments/${filename}`);

    } catch (error) {
        console.error("\n❌ Testnet deployment failed:", error);
        process.exit(1);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
