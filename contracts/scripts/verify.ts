import fs from "fs";
import path from "path";

async function main() {
  // Get deployment file from environment variable or command line args
  let deploymentFile = process.env.DEPLOYMENT_FILE;
  
  if (!deploymentFile) {
    // Filter out hardhat-specific arguments
    const args = process.argv.filter(arg => 
      !arg.includes('hardhat') && 
      !arg.includes('scripts/verify') && 
      !arg.startsWith('--') &&
      arg.endsWith('.json')
    );

    if (args.length < 1) {
      console.log("\n📋 Usage:");
      console.log("DEPLOYMENT_FILE=deployments/deployment-xxx.json npx hardhat run scripts/verify.ts --network <network>");
      
      // Try to find the latest deployment file
      const deploymentsDir = path.join(process.cwd(), 'deployments');
      if (fs.existsSync(deploymentsDir)) {
        const files = fs.readdirSync(deploymentsDir)
          .filter(f => f.endsWith('.json'))
          .map(f => ({
            name: f,
            time: fs.statSync(path.join(deploymentsDir, f)).mtime.getTime()
          }))
          .sort((a, b) => b.time - a.time);
        
        if (files.length > 0) {
          console.log("\n📁 Available deployments:");
          files.slice(0, 5).forEach((f, i) => {
            console.log(`   ${i + 1}. ${f.name}`);
          });
          console.log("\nUsing latest deployment...");
          deploymentFile = files[0].name;
        }
      }
      
      if (!deploymentFile) {
        process.exit(1);
      }
    } else {
      deploymentFile = args[0];
    }
  }

  const deploymentPath = path.isAbsolute(deploymentFile)
    ? deploymentFile
    : path.join(process.cwd(), 'deployments', path.basename(deploymentFile));

  if (!fs.existsSync(deploymentPath)) {
    console.error(`Deployment file not found: ${deploymentPath}`);
    process.exit(1);
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));
  console.log(`\n🔍 Verification commands for: ${path.basename(deploymentFile)}`);
  console.log(`Network: ${deployment.network}\n`);

  // Check if local network
  if (deployment.network === 'hardhat' || deployment.network === 'localhost') {
    console.log("⚠️  Cannot verify contracts on local network.");
    console.log("Deploy to a testnet (sepolia, etc.) to verify contracts.\n");
    return;
  }

  // Determine Pyth address based on network
  const pythAddress = deployment.network === 'sepolia' ?
    "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21" :
    "0x4305FB66699C3B2702D4d05CF36551390A4c69C6";

  console.log("=== Verification Commands ===\n");
  console.log("Run these commands to verify your contracts:\n");

  // Generate verification commands
  const commands: string[] = [];

  if (deployment.mockTokens) {
    console.log("# Mock Tokens");
    if (deployment.mockTokens.USDC) {
      commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.mockTokens.USDC} "Mock USDC" "USDC" 6`);
    }
    if (deployment.mockTokens.USDT) {
      commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.mockTokens.USDT} "Mock USDT" "USDT" 6`);
    }
    if (deployment.mockTokens.DAI) {
      commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.mockTokens.DAI} "Mock DAI" "DAI" 18`);
    }
    console.log(commands.join('\n'));
    console.log();
    commands.length = 0;
  }

  console.log("# Core Contracts");
  if (deployment.contracts.PythPriceMonitor) {
    commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.contracts.PythPriceMonitor} ${pythAddress}`);
  }
  if (deployment.contracts.DEXAggregator) {
    commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.contracts.DEXAggregator}`);
  }
  if (deployment.contracts.CrashGuardCore) {
    commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.contracts.CrashGuardCore}`);
  }
  if (deployment.contracts.EmergencyExecutor) {
    commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.contracts.EmergencyExecutor} ${deployment.contracts.CrashGuardCore} ${deployment.contracts.DEXAggregator}`);
  }
  if (deployment.contracts.LitRelayContract) {
    commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.contracts.LitRelayContract}`);
  }
  if (deployment.contracts.LitProtocolIntegration) {
    commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.contracts.LitProtocolIntegration} ${deployment.contracts.LitRelayContract}`);
  }
  if (deployment.contracts.CrossChainManager) {
    commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.contracts.CrossChainManager} ${deployment.contracts.LitRelayContract} ${deployment.contracts.LitProtocolIntegration}`);
  }
  if (deployment.contracts.CrossChainEmergencyCoordinator) {
    commands.push(`npx hardhat verify --network ${deployment.network} ${deployment.contracts.CrossChainEmergencyCoordinator} ${deployment.contracts.LitRelayContract} ${deployment.contracts.LitProtocolIntegration} ${deployment.contracts.CrossChainManager}`);
  }

  console.log(commands.join('\n'));
  console.log("\n💡 Tip: Copy and run these commands one by one, or save them to a shell script.\n");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
