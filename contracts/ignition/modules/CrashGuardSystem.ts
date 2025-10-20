import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const CrashGuardSystemModule: any = buildModule("CrashGuardSystem", (m) => {
    // Get parameters with defaults
    const pythPriceFeedAddress = m.getParameter(
        "pythPriceFeedAddress",
        "0x4305FB66699C3B2702D4d05CF36551390A4c69C6"
    );

    // 1. Deploy PythPriceMonitor
    const pythPriceMonitor = m.contract("PythPriceMonitor", [pythPriceFeedAddress]);

    // 2. Deploy DEXAggregator
    const dexAggregator = m.contract("DEXAggregator");

    // 3. Deploy CrashGuardCore
    const crashGuardCore = m.contract("CrashGuardCore");

    // 4. Deploy EmergencyExecutor
    const emergencyExecutor = m.contract("EmergencyExecutor", [
        crashGuardCore,
        dexAggregator
    ]);

    // 5. Deploy LitRelayContract
    const litRelayContract = m.contract("LitRelayContract");

    // 6. Deploy LitProtocolIntegration
    const litProtocolIntegration = m.contract("LitProtocolIntegration", [
        litRelayContract
    ]);

    // 7. Deploy CrossChainManager
    const crossChainManager = m.contract("CrossChainManager", [
        litRelayContract,
        litProtocolIntegration
    ]);

    // 8. Deploy CrossChainEmergencyCoordinator
    const crossChainEmergencyCoordinator = m.contract("CrossChainEmergencyCoordinator", [
        litRelayContract,
        litProtocolIntegration,
        crossChainManager
    ]);

    // 9. Configure contracts
    m.call(crashGuardCore, "setEmergencyExecutor", [emergencyExecutor]);
    m.call(emergencyExecutor, "setLitProtocolIntegration", [litProtocolIntegration]);
    m.call(emergencyExecutor, "setLitRelayContract", [litRelayContract]);
    m.call(crashGuardCore, "setLitProtocolIntegration", [litProtocolIntegration]);
    m.call(crashGuardCore, "setLitRelayContract", [litRelayContract]);

    return {
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

export default CrashGuardSystemModule;
