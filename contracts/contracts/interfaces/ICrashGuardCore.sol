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
}
