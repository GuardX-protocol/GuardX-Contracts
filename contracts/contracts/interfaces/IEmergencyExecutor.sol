// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface IEmergencyExecutor {
    struct EmergencyAction {
        address user;
        address[] assetsToConvert;
        address targetStablecoin;
        uint256 maxSlippage;
        uint256 deadline;
    }

    struct ExecutionResult {
        bool success;
        uint256 amountConverted;
        uint256 actualSlippage;
        string errorMessage;
    }

    event EmergencyExecutionStarted(address indexed user, uint256 timestamp);
    event EmergencyExecutionCompleted(address indexed user, ExecutionResult result);
    event BatchExecutionCompleted(uint256 executionsCount, uint256 successCount);

    function executeEmergencyProtection(address user) external returns (ExecutionResult memory);
    function emergencyConvertToStable(
        address[] calldata assets,
        address targetStable,
        uint256 maxSlippage
    ) external returns (ExecutionResult memory);
    function batchEmergencyActions(EmergencyAction[] calldata actions) external returns (ExecutionResult[] memory);
    function setAccessControl(address controller, bool hasAccess) external;
    
    // Lit Action integration
    function executeLitActionTriggeredProtection(
        address user,
        string calldata litActionId,
        bytes calldata executionData
    ) external returns (ExecutionResult memory);
    
    function authorizeLitAction(string calldata litActionId) external;
    function revokeLitActionAuthorization(string calldata litActionId) external;
    function isLitActionAuthorized(string calldata litActionId) external view returns (bool);
}