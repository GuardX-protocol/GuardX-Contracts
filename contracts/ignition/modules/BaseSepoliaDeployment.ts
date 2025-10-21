import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const BaseSepoliaDeploymentModule: any = buildModule("BaseSepoliaDeployment", (m) => {
    const pythContract = m.getParameter(
        "pythContract",
        "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729"
    );

    const oneInchRouter = m.getParameter(
        "oneInchRouter",
        "0x1111111254EEB25477B68fb85Ed929f73A960582"
    );

    const uniswapRouter = m.getParameter(
        "uniswapRouter",
        "0x2626664c2603336E57B271c5C0b26F421741e481"
    );

    const uniswapQuoter = m.getParameter(
        "uniswapQuoter",
        "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a"
    );

    const pythPriceMonitor = m.contract("PythPriceMonitor", [pythContract]);

    const dexAggregator = m.contract("DEXAggregator", [
        oneInchRouter,
        uniswapRouter,
        uniswapQuoter
    ]);

    const crashGuardCore = m.contract("CrashGuardCore");

    const emergencyExecutor = m.contract("EmergencyExecutor", [
        crashGuardCore,
        dexAggregator
    ]);

    const litRelayContract = m.contract("LitRelayContract");

    const litProtocolIntegration = m.contract("LitProtocolIntegration", [
        litRelayContract
    ]);

    const crossChainManager = m.contract("CrossChainManager", [
        litRelayContract,
        litProtocolIntegration
    ]);

    const crossChainEmergencyCoordinator = m.contract("CrossChainEmergencyCoordinator", [
        litRelayContract,
        litProtocolIntegration,
        crossChainManager
    ]);

    const portfolioRebalancer = m.contract("PortfolioRebalancer", [
        crashGuardCore,
        dexAggregator,
        pythPriceMonitor
    ]);

    m.call(crashGuardCore, "setEmergencyExecutor", [emergencyExecutor], {
        id: "CrashGuardCore_setEmergencyExecutor"
    });
    m.call(crashGuardCore, "setLitProtocolIntegration", [litProtocolIntegration], {
        id: "CrashGuardCore_setLitProtocolIntegration"
    });
    m.call(crashGuardCore, "setLitRelayContract", [litRelayContract], {
        id: "CrashGuardCore_setLitRelayContract"
    });

    m.call(pythPriceMonitor, "setCrashGuardCore", [crashGuardCore], {
        id: "PythPriceMonitor_setCrashGuardCore"
    });

    m.call(dexAggregator, "setAuthorizedCaller", [emergencyExecutor, true], {
        id: "DEXAggregator_authorizeEmergencyExecutor"
    });
    m.call(dexAggregator, "setAuthorizedCaller", [portfolioRebalancer, true], {
        id: "DEXAggregator_authorizePortfolioRebalancer"
    });

    m.call(litProtocolIntegration, "setAuthorizedIntegrator", [crashGuardCore, true], {
        id: "LitProtocolIntegration_authorizeCrashGuardCore"
    });
    m.call(litProtocolIntegration, "setAuthorizedIntegrator", [emergencyExecutor, true], {
        id: "LitProtocolIntegration_authorizeEmergencyExecutor"
    });

    m.call(litRelayContract, "setAuthorizedRelayer", [crossChainManager, true], {
        id: "LitRelayContract_authorizeCrossChainManager"
    });
    m.call(litRelayContract, "setAuthorizedRelayer", [crossChainEmergencyCoordinator, true], {
        id: "LitRelayContract_authorizeCrossChainEmergencyCoordinator"
    });

    return {
        pythPriceMonitor,
        dexAggregator,
        crashGuardCore,
        emergencyExecutor,
        litRelayContract,
        litProtocolIntegration,
        crossChainManager,
        crossChainEmergencyCoordinator,
        portfolioRebalancer
    };
});

export default BaseSepoliaDeploymentModule;
