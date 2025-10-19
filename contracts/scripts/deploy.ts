import { ethers } from "hardhat";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";

dotenv.config();

interface DeployedContracts {
    pythPriceMonitor: any;
    dexAggregator: any;
    crashGuardCore: any;
    emergencyExecutor: any;
    litRelayContract: any;
    litProtocolIntegration: any;
    crossChainManager: any;
    crossChainEmergencyCoordinator: any;
}

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);
    console.log("Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)));

    const deployedContracts: Partial<DeployedContracts> = {};

    try {
        // 1. Deploy PythPriceMonitor
        console.log("\n1. Deploying PythPriceMonitor...");
        const PythPriceMonitor = await ethers.getContractFactory("PythPriceMonitor");
        const pythPriceMonitor = await PythPriceMonitor.deploy(
            process.env.PYTH_PRICE_FEED_ADDRESS || "0x4305FB66699C3B2702D4d05CF36551390A4c69C6" // Pyth mainnet
        );
        await pythPriceMonitor.waitForDeployment();
        deployedContracts.pythPriceMonitor = pythPriceMonitor;
        console.log("PythPriceMonitor deployed to:", await pythPriceMonitor.getAddress());

        // 2. Deploy DEXAggregator (placeholder implementation)
        console.log("\n2. Deploying DEXAggregator...");
        const DEXAggregator = await ethers.getContractFactory("DEXAggregator");
        const dexAggregator = await DEXAggregator.deploy();
        await dexAggregator.waitForDeployment();
        deployedContracts.dexAggregator = dexAggregator;
        console.log("DEXAggregator deployed to:", await dexAggregator.getAddress());

        // 3. Deploy CrashGuardCore
        console.log("\n3. Deploying CrashGuardCore...");
        const CrashGuardCore = await ethers.getContractFactory("CrashGuardCore");
        const crashGuardCore = await CrashGuardCore.deploy();
        await crashGuardCore.waitForDeployment();
        deployedContracts.crashGuardCore = crashGuardCore;
        console.log("CrashGuardCore deployed to:", await crashGuardCore.getAddress());

        // 4. Deploy EmergencyExecutor
        console.log("\n4. Deploying EmergencyExecutor...");
        const EmergencyExecutor = await ethers.getContractFactory("EmergencyExecutor");
        const emergencyExecutor = await EmergencyExecutor.deploy(
            await crashGuardCore.getAddress(),
            await dexAggregator.getAddress()
        );
        await emergencyExecutor.waitForDeployment();
        deployedContracts.emergencyExecutor = emergencyExecutor;
        console.log("EmergencyExecutor deployed to:", await emergencyExecutor.getAddress());

        // 5. Deploy LitRelayContract
        console.log("\n5. Deploying LitRelayContract...");
        const LitRelayContract = await ethers.getContractFactory("LitRelayContract");
        const litRelayContract = await LitRelayContract.deploy();
        await litRelayContract.waitForDeployment();
        deployedContracts.litRelayContract = litRelayContract;
        console.log("LitRelayContract deployed to:", await litRelayContract.getAddress());

        // 6. Deploy LitProtocolIntegration
        console.log("\n6. Deploying LitProtocolIntegration...");
        const LitProtocolIntegration = await ethers.getContractFactory("LitProtocolIntegration");
        const litProtocolIntegration = await LitProtocolIntegration.deploy(
            await litRelayContract.getAddress()
        );
        await litProtocolIntegration.waitForDeployment();
        deployedContracts.litProtocolIntegration = litProtocolIntegration;
        console.log("LitProtocolIntegration deployed to:", await litProtocolIntegration.getAddress());

        // 7. Deploy CrossChainManager
        console.log("\n7. Deploying CrossChainManager...");
        const CrossChainManager = await ethers.getContractFactory("CrossChainManager");
        const crossChainManager = await CrossChainManager.deploy(
            await litRelayContract.getAddress(),
            await litProtocolIntegration.getAddress()
        );
        await crossChainManager.waitForDeployment();
        deployedContracts.crossChainManager = crossChainManager;
        console.log("CrossChainManager deployed to:", await crossChainManager.getAddress());

        // 8. Deploy CrossChainEmergencyCoordinator
        console.log("\n8. Deploying CrossChainEmergencyCoordinator...");
        const CrossChainEmergencyCoordinator = await ethers.getContractFactory("CrossChainEmergencyCoordinator");
        const crossChainEmergencyCoordinator = await CrossChainEmergencyCoordinator.deploy(
            await litRelayContract.getAddress(),
            await litProtocolIntegration.getAddress(),
            await crossChainManager.getAddress()
        );
        await crossChainEmergencyCoordinator.waitForDeployment();
        deployedContracts.crossChainEmergencyCoordinator = crossChainEmergencyCoordinator;
        console.log("CrossChainEmergencyCoordinator deployed to:", await crossChainEmergencyCoordinator.getAddress());

        // Configure contracts
        console.log("\n9. Configuring contracts...");

        // Set emergency executor in CrashGuardCore
        await crashGuardCore.setEmergencyExecutor(await emergencyExecutor.getAddress());
        console.log("✓ Set EmergencyExecutor in CrashGuardCore");

        // Set Lit Protocol contracts in EmergencyExecutor
        await emergencyExecutor.setLitProtocolIntegration(await litProtocolIntegration.getAddress());
        await emergencyExecutor.setLitRelayContract(await litRelayContract.getAddress());
        console.log("✓ Set Lit Protocol contracts in EmergencyExecutor");

        // Set Lit Protocol contracts in CrashGuardCore
        await crashGuardCore.setLitProtocolIntegration(await litProtocolIntegration.getAddress());
        await crashGuardCore.setLitRelayContract(await litRelayContract.getAddress());
        console.log("✓ Set Lit Protocol contracts in CrashGuardCore");

        // Skip adding supported tokens for local deployment
        // In production, add real token addresses via environment variables
        if (process.env.USDC_ADDRESS && process.env.USDT_ADDRESS && process.env.DAI_ADDRESS) {
            const supportedTokens = [
                process.env.USDC_ADDRESS,
                process.env.USDT_ADDRESS,
                process.env.DAI_ADDRESS
            ];

            for (const token of supportedTokens) {
                await crashGuardCore.addSupportedToken(token);
            }
            console.log("✓ Added supported tokens to CrashGuardCore");
        } else {
            console.log("⚠ Skipped adding supported tokens (set USDC_ADDRESS, USDT_ADDRESS, DAI_ADDRESS env vars for production)");
        }

        // Summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("PythPriceMonitor:", await pythPriceMonitor.getAddress());
        console.log("DEXAggregator:", await dexAggregator.getAddress());
        console.log("CrashGuardCore:", await crashGuardCore.getAddress());
        console.log("EmergencyExecutor:", await emergencyExecutor.getAddress());
        console.log("LitRelayContract:", await litRelayContract.getAddress());
        console.log("LitProtocolIntegration:", await litProtocolIntegration.getAddress());
        console.log("CrossChainManager:", await crossChainManager.getAddress());
        console.log("CrossChainEmergencyCoordinator:", await crossChainEmergencyCoordinator.getAddress());

        // Save deployment addresses to file
        const network = await ethers.provider.getNetwork();
        const deploymentInfo = {
            network: network.name,
            chainId: network.chainId.toString(),
            deployer: deployer.address,
            timestamp: new Date().toISOString(),
            contracts: {
                PythPriceMonitor: await pythPriceMonitor.getAddress(),
                DEXAggregator: await dexAggregator.getAddress(),
                CrashGuardCore: await crashGuardCore.getAddress(),
                EmergencyExecutor: await emergencyExecutor.getAddress(),
                LitRelayContract: await litRelayContract.getAddress(),
                LitProtocolIntegration: await litProtocolIntegration.getAddress(),
                CrossChainManager: await crossChainManager.getAddress(),
                CrossChainEmergencyCoordinator: await crossChainEmergencyCoordinator.getAddress()
            }
        };

        const deploymentsDir = path.join(__dirname, '../deployments');
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }

        const filename = `deployment-${network.chainId}-${Date.now()}.json`;
        fs.writeFileSync(
            path.join(deploymentsDir, filename),
            JSON.stringify(deploymentInfo, null, 2)
        );
        console.log(`\nDeployment info saved to: deployments/${filename}`);

    } catch (error) {
        console.error("Deployment failed:", error);
        process.exit(1);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

export {};