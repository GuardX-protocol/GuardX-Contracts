// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICrashGuardCore {
    struct Asset {
        address tokenAddress;
        uint256 amount;
        uint256 valueUSD;
        uint8 riskLevel;
    }

    struct Portfolio {
        Asset[] assets;
        uint256 totalValue;
        uint256 lastUpdated;
        uint256 riskScore;
    }

    struct ProtectionPolicy {
        uint256 crashThreshold;
        uint256 maxSlippage;
        address[] emergencyActions;
        address stablecoinPreference;
        uint256 gasLimit;
    }

    event AssetDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event AssetWithdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event PolicyUpdated(address indexed user, ProtectionPolicy policy);
    event EmergencyProtectionTriggered(address indexed user, uint256 timestamp);
    
    // New events for permissionless and cross-chain functionality
    event CrossChainDepositProcessed(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 indexed sourceChain,
        bytes32 depositHash
    );
    event PermissionlessModeUpdated(bool enabled);
    event TokenBlacklistUpdated(address indexed token, bool blacklisted);
    event BridgeAuthorizationUpdated(address indexed bridge, bool authorized);
    event StablecoinAutoDetected(address indexed token, string symbol);

    function depositAsset(address token, uint256 amount) external payable;
    function withdrawAsset(address token, uint256 amount) external;
    function getUserPortfolio(
        address user
    ) external view returns (Portfolio memory);
    function setProtectionPolicy(ProtectionPolicy memory policy) external;
    function getProtectionPolicy(
        address user
    ) external view returns (ProtectionPolicy memory);
    function getUserBalance(address user, address token) external view returns (uint256);
    function emergencyWithdraw(
        address user,
        address token,
        uint256 amount
    ) external;
    
    // PKP-based operations
    function pkpDepositAsset(
        address user,
        address token,
        uint256 amount,
        string calldata litActionId
    ) external payable;
    
    function pkpWithdrawAsset(
        address user,
        address token,
        uint256 amount,
        string calldata litActionId
    ) external;
    
    function setupPKPAuthorization(
        address user,
        address pkpAddress,
        string calldata litActionId
    ) external;
    
    function revokePKPAuthorization(address user) external;
    
    function processLitActionExecution(
        address user,
        bytes32 executionHash,
        string calldata litActionId
    ) external;
    
    function isPKPAuthorized(address user) external view returns (bool);
    
    function getUserLitAction(address user) external view returns (string memory);
    
    // Cross-chain functionality
    function crossChainDeposit(
        address user,
        address token,
        uint256 amount,
        uint256 sourceChain,
        bytes32 depositHash
    ) external;
    
    function setPermissionlessMode(bool _permissionless) external;
    function setTokenBlacklist(address token, bool blacklisted) external;
    function setAuthorizedBridge(address bridge, bool authorized) external;
    function isTokenSupported(address token) external view returns (bool);
    function getTokenInfo(address token) external view returns (
        bool supported,
        bool stablecoin,
        bool blacklisted
    );
}
