import { ethers } from "hardhat";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";

dotenv.config();

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying to testnet with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)));

  // Deploy with testnet-specific configurations
  const network = await ethers.provider.getNetwork();
  console.log("Network:", network.name, "Chain ID:", network.chainId);

  try {
    // 1. Deploy mock tokens for testing
    console.log("\n1. Deploying mock tokens...");
    const MockERC20 = await ethers.getContractFactory("MockERC20");

    const mockUSDC = await MockERC20.deploy("Mock USDC", "USDC", 6);
    await mockUSDC.waitForDeployment();
    console.log("Mock USDC deployed to:", await mockUSDC.getAddress());

    const mockUSDT = await MockERC20.deploy("Mock USDT", "USDT", 6);
    await mockUSDT.waitForDeployment();
    console.log("Mock USDT deployed to:", await mockUSDT.getAddress());

    const mockDAI = await MockERC20.deploy("Mock DAI", "DAI", 18);
    await mockDAI.waitForDeployment();
    console.log("Mock DAI deployed to:", await mockDAI.getAddress());

    // 2. Deploy PythPriceMonitor with testnet Pyth address
    console.log("\n2. Deploying PythPriceMonitor...");
    const PythPriceMonitor = await ethers.getContractFactory("PythPriceMonitor");
    const pythAddress = network.chainId === 11155111n ?
      "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21" : // Sepolia
      "0x4305FB66699C3B2702D4d05CF36551390A4c69C6";   // Default

    const pythPriceMonitor = await PythPriceMonitor.deploy(pythAddress);
    await pythPriceMonitor.waitForDeployment();
    console.log("PythPriceMonitor deployed to:", await pythPriceMonitor.getAddress());

    // 3. Deploy DEXAggregator
    console.log("\n3. Deploying DEXAggregator...");
    const DEXAggregator = await ethers.getContractFactory("DEXAggregator");
    const dexAggregator = await DEXAggregator.deploy();
    await dexAggregator.waitForDeployment();
    console.log("DEXAggregator deployed to:", await dexAggregator.getAddress());

    // 4. Deploy CrashGuardCore
    console.log("\n4. Deploying CrashGuardCore...");
    const CrashGuardCore = await ethers.getContractFactory("CrashGuardCore");
    const crashGuardCore = await CrashGuardCore.deploy();
    await crashGuardCore.waitForDeployment();
    console.log("CrashGuardCore deployed to:", await crashGuardCore.getAddress());

    // 5. Deploy EmergencyExecutor
    console.log("\n5. Deploying EmergencyExecutor...");
    const EmergencyExecutor = await ethers.getContractFactory("EmergencyExecutor");
    const emergencyExecutor = await EmergencyExecutor.deploy(
      await crashGuardCore.getAddress(),
      await dexAggregator.getAddress()
    );
    await emergencyExecutor.waitForDeployment();
    console.log("EmergencyExecutor deployed to:", await emergencyExecutor.getAddress());

    // 6. Deploy Lit Protocol contracts
    console.log("\n6. Deploying Lit Protocol contracts...");
    const LitRelayContract = await ethers.getContractFactory("LitRelayContract");
    const litRelayContract = await LitRelayContract.deploy();
    await litRelayContract.waitForDeployment();
    console.log("LitRelayContract deployed to:", await litRelayContract.getAddress());

    const LitProtocolIntegration = await ethers.getContractFactory("LitProtocolIntegration");
    const litProtocolIntegration = await LitProtocolIntegration.deploy(
      await litRelayContract.getAddress()
    );
    await litProtocolIntegration.waitForDeployment();
    console.log("LitProtocolIntegration deployed to:", await litProtocolIntegration.getAddress());

    // 7. Configure contracts
    console.log("\n7. Configuring contracts...");

    // Set emergency executor
    await crashGuardCore.setEmergencyExecutor(await emergencyExecutor.getAddress());
    console.log("✓ Set EmergencyExecutor in CrashGuardCore");

    // Add supported tokens
    await crashGuardCore.addSupportedToken(await mockUSDC.getAddress());
    await crashGuardCore.addSupportedToken(await mockUSDT.getAddress());
    await crashGuardCore.addSupportedToken(await mockDAI.getAddress());
    console.log("✓ Added supported tokens");

    // Set Lit Protocol contracts
    await crashGuardCore.setLitProtocolIntegration(await litProtocolIntegration.getAddress());
    await crashGuardCore.setLitRelayContract(await litRelayContract.getAddress());
    await emergencyExecutor.setLitProtocolIntegration(await litProtocolIntegration.getAddress());
    await emergencyExecutor.setLitRelayContract(await litRelayContract.getAddress());
    console.log("✓ Set Lit Protocol contracts");

    // Mint some test tokens to deployer for testing
    const testAmount = ethers.parseEther("10000");
    await mockUSDC.mint(deployer.address, testAmount / 1000000000000n); // Adjust for 6 decimals
    await mockUSDT.mint(deployer.address, testAmount / 1000000000000n); // Adjust for 6 decimals
    await mockDAI.mint(deployer.address, testAmount);
    console.log("✓ Minted test tokens to deployer");

    // Summary
    console.log("\n=== TESTNET DEPLOYMENT SUMMARY ===");
    console.log("Network:", network.name, "Chain ID:", network.chainId.toString());
    console.log("Deployer:", deployer.address);
    console.log("\nMock Tokens:");
    console.log("USDC:", await mockUSDC.getAddress());
    console.log("USDT:", await mockUSDT.getAddress());
    console.log("DAI:", await mockDAI.getAddress());
    console.log("\nCore Contracts:");
    console.log("PythPriceMonitor:", await pythPriceMonitor.getAddress());
    console.log("DEXAggregator:", await dexAggregator.getAddress());
    console.log("CrashGuardCore:", await crashGuardCore.getAddress());
    console.log("EmergencyExecutor:", await emergencyExecutor.getAddress());
    console.log("\nLit Protocol:");
    console.log("LitRelayContract:", await litRelayContract.getAddress());
    console.log("LitProtocolIntegration:", await litProtocolIntegration.getAddress());

    // Save testnet deployment info
    const deploymentInfo = {
      network: network.name,
      chainId: network.chainId.toString(),
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      mockTokens: {
        USDC: await mockUSDC.getAddress(),
        USDT: await mockUSDT.getAddress(),
        DAI: await mockDAI.getAddress()
      },
      contracts: {
        PythPriceMonitor: await pythPriceMonitor.getAddress(),
        DEXAggregator: await dexAggregator.getAddress(),
        CrashGuardCore: await crashGuardCore.getAddress(),
        EmergencyExecutor: await emergencyExecutor.getAddress(),
        LitRelayContract: await litRelayContract.getAddress(),
        LitProtocolIntegration: await litProtocolIntegration.getAddress()
      }
    };

    const deploymentsDir = path.join(__dirname, '../deployments');
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    const filename = `testnet-deployment-${network.chainId}-${Date.now()}.json`;
    fs.writeFileSync(
      path.join(deploymentsDir, filename),
      JSON.stringify(deploymentInfo, null, 2)
    );
    console.log(`\nTestnet deployment info saved to: deployments/${filename}`);

  } catch (error) {
    console.error("Testnet deployment failed:", error);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

export { };