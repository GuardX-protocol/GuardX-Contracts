import { network } from "hardhat";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";

dotenv.config();

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

async function main() {
    console.log("\n🚀 Starting deployment with Hardhat Ignition...\n");

    try {
        const connection: any = await network.connect();
        const { ethers } = connection;

        const [deployer] = await ethers.getSigners();
        console.log("Deploying with:", deployer.address);

        const balance = await ethers.provider.getBalance(deployer.address);
        console.log("Balance:", ethers.formatEther(balance), "ETH");

        const nonce = await ethers.provider.getTransactionCount(deployer.address);
        console.log("Current nonce:", nonce, "\n");

        const PYTH_CONTRACT = process.env.PYTH_CONTRACT;
        const ONEINCH_ROUTER = process.env.ONEINCH_ROUTER;
        const UNISWAP_ROUTER = process.env.UNISWAP_ROUTER;
        const UNISWAP_QUOTER = process.env.UNISWAP_QUOTER;

        console.log("1. Deploying PythPriceMonitor...");
        const PythPriceMonitor = await ethers.getContractFactory("PythPriceMonitor");
        const pythPriceMonitor = await PythPriceMonitor.deploy(PYTH_CONTRACT);
        await pythPriceMonitor.waitForDeployment();
        console.log("✓ PythPriceMonitor:", await pythPriceMonitor.getAddress());
        await sleep(2000);

        console.log("\n2. Deploying DEXAggregator...");
        const DEXAggregator = await ethers.getContractFactory("DEXAggregator");
        const dexAggregator = await DEXAggregator.deploy(ONEINCH_ROUTER, UNISWAP_ROUTER, UNISWAP_QUOTER);
        await dexAggregator.waitForDeployment();
        console.log("✓ DEXAggregator:", await dexAggregator.getAddress());
        await sleep(2000);

        console.log("\n3. Deploying CrashGuardCore...");
        const CrashGuardCore = await ethers.getContractFactory("CrashGuardCore");
        const crashGuardCore = await CrashGuardCore.deploy();
        await crashGuardCore.waitForDeployment();
        console.log("✓ CrashGuardCore:", await crashGuardCore.getAddress());
        await sleep(2000);

        console.log("\n4. Deploying EmergencyExecutor...");
        const EmergencyExecutor = await ethers.getContractFactory("EmergencyExecutor");
        const emergencyExecutor = await EmergencyExecutor.deploy(
            await crashGuardCore.getAddress(),
            await dexAggregator.getAddress()
        );
        await emergencyExecutor.waitForDeployment();
        console.log("✓ EmergencyExecutor:", await emergencyExecutor.getAddress());
        await sleep(2000);

        console.log("\n5. Deploying LitRelayContract...");
        const LitRelayContract = await ethers.getContractFactory("LitRelayContract");
        const litRelayContract = await LitRelayContract.deploy();
        await litRelayContract.waitForDeployment();
        console.log("✓ LitRelayContract:", await litRelayContract.getAddress());
        await sleep(2000);

        console.log("\n6. Deploying LitProtocolIntegration...");
        const LitProtocolIntegration = await ethers.getContractFactory("LitProtocolIntegration");
        const litProtocolIntegration = await LitProtocolIntegration.deploy(await litRelayContract.getAddress());
        await litProtocolIntegration.waitForDeployment();
        console.log("✓ LitProtocolIntegration:", await litProtocolIntegration.getAddress());
        await sleep(2000);

        console.log("\n7. Deploying CrossChainManager...");
        const CrossChainManager = await ethers.getContractFactory("CrossChainManager");
        const crossChainManager = await CrossChainManager.deploy(
            await litRelayContract.getAddress(),
            await litProtocolIntegration.getAddress()
        );
        await crossChainManager.waitForDeployment();
        console.log("✓ CrossChainManager:", await crossChainManager.getAddress());
        await sleep(2000);

        console.log("\n8. Deploying CrossChainEmergencyCoordinator...");
        const CrossChainEmergencyCoordinator = await ethers.getContractFactory("CrossChainEmergencyCoordinator");
        const crossChainEmergencyCoordinator = await CrossChainEmergencyCoordinator.deploy(
            await litRelayContract.getAddress(),
            await litProtocolIntegration.getAddress(),
            await crossChainManager.getAddress()
        );
        await crossChainEmergencyCoordinator.waitForDeployment();
        console.log("✓ CrossChainEmergencyCoordinator:", await crossChainEmergencyCoordinator.getAddress());
        await sleep(2000);

        console.log("\n9. Deploying PortfolioRebalancer...");
        const PortfolioRebalancer = await ethers.getContractFactory("PortfolioRebalancer");
        const portfolioRebalancer = await PortfolioRebalancer.deploy(
            await crashGuardCore.getAddress(),
            await dexAggregator.getAddress(),
            await pythPriceMonitor.getAddress()
        );
        await portfolioRebalancer.waitForDeployment();
        console.log("✓ PortfolioRebalancer:", await portfolioRebalancer.getAddress());
        await sleep(2000);

        console.log("\n✅ All contracts deployed!\n");

        console.log("📝 Configuring contracts...");
        const tx1 = await crashGuardCore.setEmergencyExecutor(await emergencyExecutor.getAddress());
        await tx1.wait();
        await sleep(1000);

        const tx2 = await crashGuardCore.setLitProtocolIntegration(await litProtocolIntegration.getAddress());
        await tx2.wait();
        await sleep(1000);

        const tx3 = await crashGuardCore.setLitRelayContract(await litRelayContract.getAddress());
        await tx3.wait();
        await sleep(1000);

        const tx4 = await pythPriceMonitor.setCrashGuardCore(await crashGuardCore.getAddress());
        await tx4.wait();
        await sleep(1000);

        const tx5 = await dexAggregator.setAuthorizedCaller(await emergencyExecutor.getAddress(), true);
        await tx5.wait();
        await sleep(1000);

        const tx6 = await dexAggregator.setAuthorizedCaller(await portfolioRebalancer.getAddress(), true);
        await tx6.wait();
        await sleep(1000);

        const tx7 = await emergencyExecutor.setAccessControl(deployer.address, true);
        await tx7.wait();
        await sleep(1000);

        const tx8 = await litProtocolIntegration.setAuthorizedIntegrator(await crashGuardCore.getAddress(), true);
        await tx8.wait();
        await sleep(1000);

        const tx9 = await litProtocolIntegration.setAuthorizedIntegrator(await emergencyExecutor.getAddress(), true);
        await tx9.wait();
        await sleep(1000);

        const tx10 = await litRelayContract.setAuthorizedRelayer(await crossChainManager.getAddress(), true);
        await tx10.wait();
        await sleep(1000);

        const tx11 = await litRelayContract.setAuthorizedRelayer(await crossChainEmergencyCoordinator.getAddress(), true);
        await tx11.wait();

        console.log("✓ Configuration complete\n");

        const addresses = {
            PythPriceMonitor: await pythPriceMonitor.getAddress(),
            DEXAggregator: await dexAggregator.getAddress(),
            CrashGuardCore: await crashGuardCore.getAddress(),
            EmergencyExecutor: await emergencyExecutor.getAddress(),
            LitRelayContract: await litRelayContract.getAddress(),
            LitProtocolIntegration: await litProtocolIntegration.getAddress(),
            CrossChainManager: await crossChainManager.getAddress(),
            CrossChainEmergencyCoordinator: await crossChainEmergencyCoordinator.getAddress(),
            PortfolioRebalancer: await portfolioRebalancer.getAddress()
        };

        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("Network: Base Sepolia (Chain ID: 84532)");
        console.log("\nDeployed Contracts:");
        Object.entries(addresses).forEach(([name, address]) => {
            console.log(`${name}: ${address}`);
        });

        console.log("\nExternal Contracts:");
        console.log(`Pyth Oracle: ${PYTH_CONTRACT}`);
        console.log(`1inch Router: ${ONEINCH_ROUTER}`);
        console.log(`Uniswap Router: ${UNISWAP_ROUTER}`);
        console.log(`Uniswap Quoter: ${UNISWAP_QUOTER}`);

        const deploymentsDir = path.join(process.cwd(), 'deployments');
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }

        
        const networkName = (await network.connect()).networkName;

        const deploymentInfo = {
            network: (await network.connect()).networkName,
            chainId: (await network.connect()).networkConfig.chainId,
            timestamp: new Date().toISOString(),
            contracts: addresses,
            externalContracts: {
                PythContract: PYTH_CONTRACT,
                OneInchRouter: ONEINCH_ROUTER,
                UniswapRouter: UNISWAP_ROUTER,
                UniswapQuoter: UNISWAP_QUOTER
            }
        };

        const filename = `deployment-${networkName}-${Date.now()}.json`;
        fs.writeFileSync(
            path.join(deploymentsDir, filename),
            JSON.stringify(deploymentInfo, null, 2)
        );
        console.log(`\n💾 Saved to: deployments/${filename}`);

        console.log("\n=== VERIFICATION COMMANDS ===");
        console.log(`npx hardhat verify --network ${networkName} ${addresses.PythPriceMonitor} ${PYTH_CONTRACT}`);
        console.log(`npx hardhat verify --network ${networkName} ${addresses.DEXAggregator} ${ONEINCH_ROUTER} ${UNISWAP_ROUTER} ${UNISWAP_QUOTER}`);
        console.log(`npx hardhat verify --network ${networkName} ${addresses.CrashGuardCore}`);
        console.log(`npx hardhat verify --network ${networkName} ${addresses.EmergencyExecutor} ${addresses.CrashGuardCore} ${addresses.DEXAggregator}`);
        console.log(`npx hardhat verify --network ${networkName} ${addresses.LitRelayContract}`);
        console.log(`npx hardhat verify --network ${networkName} ${addresses.LitProtocolIntegration} ${addresses.LitRelayContract}`);
        console.log(`npx hardhat verify --network ${networkName} ${addresses.CrossChainManager} ${addresses.LitRelayContract} ${addresses.LitProtocolIntegration}`);
        console.log(`npx hardhat verify --network ${networkName} ${addresses.CrossChainEmergencyCoordinator} ${addresses.LitRelayContract} ${addresses.LitProtocolIntegration} ${addresses.CrossChainManager}`);
        console.log(`npx hardhat verify --network ${networkName} ${addresses.PortfolioRebalancer} ${addresses.CrashGuardCore} ${addresses.DEXAggregator} ${addresses.PythPriceMonitor}`);

    } catch (error) {
        console.error("\n❌ Deployment failed:", error);
        process.exit(1);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
