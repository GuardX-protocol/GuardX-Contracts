import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TestnetDeploymentModule: any = buildModule("TestnetDeployment", (m) => {
    // Get parameters with defaults
    const pythPriceFeedAddress = m.getParameter(
        "pythPriceFeedAddress",
        "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21" // Sepolia default
    );

    // 1. Deploy mock tokens for testing
    const mockUSDC = m.contract("MockERC20", ["Mock USDC", "USDC", 6], { id: "MockUSDC" });
    const mockUSDT = m.contract("MockERC20", ["Mock USDT", "USDT", 6], { id: "MockUSDT" });
    const mockDAI = m.contract("MockERC20", ["Mock DAI", "DAI", 18], { id: "MockDAI" });

    // 2. Deploy PythPriceMonitor
    const pythPriceMonitor = m.contract("PythPriceMonitor", [pythPriceFeedAddress]);

    // 3. Deploy DEXAggregator
    const dexAggregator = m.contract("DEXAggregator");

    // 4. Deploy CrashGuardCore
    const crashGuardCore = m.contract("CrashGuardCore");

    // 5. Deploy EmergencyExecutor
    const emergencyExecutor = m.contract("EmergencyExecutor", [
        crashGuardCore,
        dexAggregator
    ]);

    // 6. Deploy LitRelayContract
    const litRelayContract = m.contract("LitRelayContract");

    // 7. Deploy LitProtocolIntegration
    const litProtocolIntegration = m.contract("LitProtocolIntegration", [
        litRelayContract
    ]);

    // 8. Deploy CrossChainManager
    const crossChainManager = m.contract("CrossChainManager", [
        litRelayContract,
        litProtocolIntegration
    ]);

    // 9. Deploy CrossChainEmergencyCoordinator
    const crossChainEmergencyCoordinator = m.contract("CrossChainEmergencyCoordinator", [
        litRelayContract,
        litProtocolIntegration,
        crossChainManager
    ]);

    // 10. Configure contracts
    m.call(crashGuardCore, "setEmergencyExecutor", [emergencyExecutor]);
    m.call(emergencyExecutor, "setLitProtocolIntegration", [litProtocolIntegration]);
    m.call(emergencyExecutor, "setLitRelayContract", [litRelayContract]);
    m.call(crashGuardCore, "setLitProtocolIntegration", [litProtocolIntegration]);
    m.call(crashGuardCore, "setLitRelayContract", [litRelayContract]);

    // 11. Add supported tokens
    m.call(crashGuardCore, "addSupportedToken", [mockUSDC]);
    m.call(crashGuardCore, "addSupportedToken", [mockUSDT]);
    m.call(crashGuardCore, "addSupportedToken", [mockDAI]);

    return {
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
    };
});

export default TestnetDeploymentModule;
