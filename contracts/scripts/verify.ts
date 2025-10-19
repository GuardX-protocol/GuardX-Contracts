import { run } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
  const args = process.argv.slice(2);
  
  if (args.length < 1) {
    console.log("Usage: npx hardhat run scripts/verify.ts --network <network> -- <deployment-file>");
    console.log("Example: npx hardhat run scripts/verify.ts --network sepolia -- deployments/testnet-deployment-11155111-1234567890.json");
    process.exit(1);
  }

  const deploymentFile = args[0];
  const deploymentPath = path.join(__dirname, '..', deploymentFile);

  if (!fs.existsSync(deploymentPath)) {
    console.error(`Deployment file not found: ${deploymentPath}`);
    process.exit(1);
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));
  console.log(`Verifying contracts from deployment: ${deploymentFile}`);
  console.log(`Network: ${deployment.network} (Chain ID: ${deployment.chainId})`);

  try {
    // Verify PythPriceMonitor
    if (deployment.contracts.PythPriceMonitor) {
      console.log("\nVerifying PythPriceMonitor...");
      await run("verify:verify", {
        address: deployment.contracts.PythPriceMonitor,
        constructorArguments: [
          deployment.chainId === "11155111" ? 
            "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21" : // Sepolia
            "0x4305FB66699C3B2702D4d05CF36551390A4c69C6"    // Default
        ]
      });
      console.log("✓ PythPriceMonitor verified");
    }

    // Verify DEXAggregator
    if (deployment.contracts.DEXAggregator) {
      console.log("\nVerifying DEXAggregator...");
      await run("verify:verify", {
        address: deployment.contracts.DEXAggregator,
        constructorArguments: []
      });
      console.log("✓ DEXAggregator verified");
    }

    // Verify CrashGuardCore
    if (deployment.contracts.CrashGuardCore) {
      console.log("\nVerifying CrashGuardCore...");
      await run("verify:verify", {
        address: deployment.contracts.CrashGuardCore,
        constructorArguments: []
      });
      console.log("✓ CrashGuardCore verified");
    }

    // Verify EmergencyExecutor
    if (deployment.contracts.EmergencyExecutor) {
      console.log("\nVerifying EmergencyExecutor...");
      await run("verify:verify", {
        address: deployment.contracts.EmergencyExecutor,
        constructorArguments: [
          deployment.contracts.CrashGuardCore,
          deployment.contracts.DEXAggregator
        ]
      });
      console.log("✓ EmergencyExecutor verified");
    }

    // Verify LitRelayContract
    if (deployment.contracts.LitRelayContract) {
      console.log("\nVerifying LitRelayContract...");
      await run("verify:verify", {
        address: deployment.contracts.LitRelayContract,
        constructorArguments: []
      });
      console.log("✓ LitRelayContract verified");
    }

    // Verify LitProtocolIntegration
    if (deployment.contracts.LitProtocolIntegration) {
      console.log("\nVerifying LitProtocolIntegration...");
      await run("verify:verify", {
        address: deployment.contracts.LitProtocolIntegration,
        constructorArguments: [deployment.contracts.LitRelayContract]
      });
      console.log("✓ LitProtocolIntegration verified");
    }

    // Verify CrossChainManager
    if (deployment.contracts.CrossChainManager) {
      console.log("\nVerifying CrossChainManager...");
      await run("verify:verify", {
        address: deployment.contracts.CrossChainManager,
        constructorArguments: [
          deployment.contracts.LitRelayContract,
          deployment.contracts.LitProtocolIntegration
        ]
      });
      console.log("✓ CrossChainManager verified");
    }

    // Verify CrossChainEmergencyCoordinator
    if (deployment.contracts.CrossChainEmergencyCoordinator) {
      console.log("\nVerifying CrossChainEmergencyCoordinator...");
      await run("verify:verify", {
        address: deployment.contracts.CrossChainEmergencyCoordinator,
        constructorArguments: [
          deployment.contracts.LitRelayContract,
          deployment.contracts.LitProtocolIntegration,
          deployment.contracts.CrossChainManager
        ]
      });
      console.log("✓ CrossChainEmergencyCoordinator verified");
    }

    // Verify mock tokens if they exist
    if (deployment.mockTokens) {
      console.log("\nVerifying mock tokens...");
      
      if (deployment.mockTokens.USDC) {
        await run("verify:verify", {
          address: deployment.mockTokens.USDC,
          constructorArguments: ["Mock USDC", "USDC", 6]
        });
        console.log("✓ Mock USDC verified");
      }

      if (deployment.mockTokens.USDT) {
        await run("verify:verify", {
          address: deployment.mockTokens.USDT,
          constructorArguments: ["Mock USDT", "USDT", 6]
        });
        console.log("✓ Mock USDT verified");
      }

      if (deployment.mockTokens.DAI) {
        await run("verify:verify", {
          address: deployment.mockTokens.DAI,
          constructorArguments: ["Mock DAI", "DAI", 18]
        });
        console.log("✓ Mock DAI verified");
      }
    }

    console.log("\n=== VERIFICATION COMPLETE ===");
    console.log("All contracts have been verified on the block explorer.");

  } catch (error) {
    console.error("Verification failed:", error);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

export {};