// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IEmergencyExecutor.sol";
import "./interfaces/ICrashGuardCore.sol";
import "./interfaces/IDEXAggregator.sol";
import "./interfaces/ILitProtocolIntegration.sol";
import "./interfaces/ILitRelayContract.sol";

/**
 * @title EmergencyExecutor
 * @dev Contract for executing emergency protection actions
 * Handles asset conversion and batch operations during market crashes
 */
contract EmergencyExecutor is IEmergencyExecutor, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Core contracts
    ICrashGuardCore public crashGuardCore;
    IDEXAggregator public dexAggregator;
    ILitProtocolIntegration public litProtocolIntegration;
    ILitRelayContract public litRelayContract;

    // Access control
    mapping(address => bool) public authorizedControllers;
    mapping(string => bool) public authorizedLitActions;

    // Emergency settings
    uint256 public constant MAX_SLIPPAGE = 5000; // 50% maximum slippage
    uint256 public constant DEFAULT_DEADLINE = 300; // 5 minutes default deadline
    uint256 public constant MAX_BATCH_SIZE = 50; // Maximum batch operations

    // Emergency state
    bool public emergencyPaused = false;
    uint256 public totalExecutions = 0;
    uint256 public successfulExecutions = 0;

    // Retry configuration
    uint256 public maxRetries = 3;
    uint256 public retryDelay = 60; // 1 minute

    mapping(address => uint256) public userLastExecution;
    mapping(address => uint256) public userExecutionCount;

    modifier onlyAuthorized() {
        require(
            authorizedControllers[msg.sender] || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    modifier notPaused() {
        require(!emergencyPaused, "Emergency paused");
        _;
    }

    modifier validSlippage(uint256 slippage) {
        require(slippage <= MAX_SLIPPAGE, "Slippage too high");
        _;
    }

    constructor(
        address _crashGuardCore,
        address _dexAggregator
    ) {
        require(_crashGuardCore != address(0), "Invalid CrashGuardCore");
        require(_dexAggregator != address(0), "Invalid DEXAggregator");

        crashGuardCore = ICrashGuardCore(_crashGuardCore);
        dexAggregator = IDEXAggregator(_dexAggregator);

        // Lit Protocol contracts can be set later via setter functions
        // This allows for flexible deployment order
    }

    /**
     * @dev Execute emergency protection for a user
     * @param user User address to protect
     * @return ExecutionResult with operation details
     */
    function executeEmergencyProtection(
        address user
    )
        external
        onlyAuthorized
        nonReentrant
        notPaused
        returns (ExecutionResult memory)
    {
        require(user != address(0), "Invalid user address");

        emit EmergencyExecutionStarted(user, block.timestamp);

        return _executeEmergencyProtectionInternal(user);
    }

    /**
     * @dev Convert specific assets to stablecoin
     * @param assets Array of asset addresses to convert
     * @param targetStable Target stablecoin address
     * @param maxSlippage Maximum allowed slippage
     * @return ExecutionResult with conversion details
     */
    function emergencyConvertToStable(
        address[] calldata assets,
        address targetStable,
        uint256 maxSlippage
    )
        external
        onlyAuthorized
        nonReentrant
        notPaused
        validSlippage(maxSlippage)
        returns (ExecutionResult memory)
    {
        require(assets.length > 0, "No assets provided");
        require(targetStable != address(0), "Invalid stablecoin");

        return
            _executeConversion(msg.sender, assets, targetStable, maxSlippage);
    }

    /**
     * @dev Execute multiple emergency actions in batch
     * @param actions Array of emergency actions to execute
     * @return Array of execution results
     */
    function batchEmergencyActions(
        EmergencyAction[] calldata actions
    )
        external
        onlyAuthorized
        nonReentrant
        notPaused
        returns (ExecutionResult[] memory)
    {
        require(actions.length > 0, "No actions provided");
        require(actions.length <= MAX_BATCH_SIZE, "Batch too large");

        ExecutionResult[] memory results = new ExecutionResult[](
            actions.length
        );
        uint256 successCount = 0;

        for (uint256 i = 0; i < actions.length; i++) {
            EmergencyAction memory action = actions[i];

            // Validate action parameters
            if (
                action.user == address(0) ||
                action.assetsToConvert.length == 0 ||
                action.targetStablecoin == address(0) ||
                action.maxSlippage > MAX_SLIPPAGE
            ) {
                results[i] = ExecutionResult({
                    success: false,
                    amountConverted: 0,
                    actualSlippage: 0,
                    errorMessage: "Invalid action parameters"
                });
                continue;
            }

            // Execute conversion
            results[i] = _executeConversion(
                action.user,
                action.assetsToConvert,
                action.targetStablecoin,
                action.maxSlippage
            );

            if (results[i].success) {
                successCount++;
            }

            // Update tracking
            userLastExecution[action.user] = block.timestamp;
            userExecutionCount[action.user]++;
            totalExecutions++;
        }

        successfulExecutions += successCount;
        emit BatchExecutionCompleted(actions.length, successCount);

        return results;
    }

    /**
     * @dev Set access control for emergency execution
     * @param controller Address to grant/revoke access
     * @param hasAccess True to grant access, false to revoke
     */
    function setAccessControl(
        address controller,
        bool hasAccess
    ) external onlyOwner {
        require(controller != address(0), "Invalid controller address");
        authorizedControllers[controller] = hasAccess;
    }

    /**
     * @dev Set CrashGuardCore contract address
     * @param _crashGuardCore New CrashGuardCore address
     */
    function setCrashGuardCore(address _crashGuardCore) external onlyOwner {
        require(_crashGuardCore != address(0), "Invalid address");
        crashGuardCore = ICrashGuardCore(_crashGuardCore);
    }

    /**
     * @dev Set DEXAggregator contract address
     * @param _dexAggregator New DEXAggregator address
     */
    function setDEXAggregator(address _dexAggregator) external onlyOwner {
        require(_dexAggregator != address(0), "Invalid address");
        dexAggregator = IDEXAggregator(_dexAggregator);
    }

    /**
     * @dev Set emergency pause state
     * @param paused True to pause, false to unpause
     */
    function setEmergencyPause(bool paused) external onlyOwner {
        emergencyPaused = paused;
    }

    /**
     * @dev Set retry configuration
     * @param _maxRetries Maximum number of retries
     * @param _retryDelay Delay between retries in seconds
     */
    function setRetryConfig(
        uint256 _maxRetries,
        uint256 _retryDelay
    ) external onlyOwner {
        require(_maxRetries <= 10, "Too many retries");
        require(_retryDelay >= 30, "Retry delay too short");

        maxRetries = _maxRetries;
        retryDelay = _retryDelay;
    }

    /**
     * @dev Get execution statistics
     * @return total Total executions
     * @return successful Successful executions
     * @return successRate Success rate in basis points
     */
    function getExecutionStats()
        external
        view
        returns (uint256 total, uint256 successful, uint256 successRate)
    {
        total = totalExecutions;
        successful = successfulExecutions;
        successRate = total > 0 ? (successful * 10000) / total : 0;
    }

    /**
     * @dev Get user execution history
     * @param user User address
     * @return lastExecution Timestamp of last execution
     * @return executionCount Total executions for user
     */
    function getUserExecutionHistory(
        address user
    ) external view returns (uint256 lastExecution, uint256 executionCount) {
        lastExecution = userLastExecution[user];
        executionCount = userExecutionCount[user];
    }

    /**
     * @dev Check if user can execute emergency protection
     * @param user User address
     * @return canExecute True if user can execute
     * @return reason Reason if cannot execute
     */
    function canExecuteEmergency(
        address user
    ) external view returns (bool canExecute, string memory reason) {
        if (emergencyPaused) {
            return (false, "Emergency paused");
        }

        if (user == address(0)) {
            return (false, "Invalid user");
        }

        // Check cooldown period (prevent spam)
        uint256 lastExecution = userLastExecution[user];
        if (lastExecution > 0 && block.timestamp - lastExecution < 300) {
            // 5 minute cooldown
            return (false, "Cooldown period active");
        }

        // Check if user has assets
        ICrashGuardCore.Portfolio memory portfolio = crashGuardCore
            .getUserPortfolio(user);
        if (portfolio.assets.length == 0) {
            return (false, "No assets to protect");
        }

        return (true, "");
    }

    /**
     * @dev Internal function to execute asset conversion
     * @param user User address
     * @param assets Assets to convert
     * @param targetStable Target stablecoin
     * @param maxSlippage Maximum slippage
     * @return ExecutionResult with conversion details
     */
    function _executeConversion(
        address user,
        address[] memory assets,
        address targetStable,
        uint256 maxSlippage
    ) private returns (ExecutionResult memory) {
        uint256 totalConverted = 0;
        uint256 totalSlippage = 0;
        uint256 successfulConversions = 0;

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];

            // Skip ETH and target stablecoin
            if (asset == address(0) || asset == targetStable) {
                continue;
            }

            // Get user's balance for this asset
            uint256 balance = crashGuardCore.getUserBalance(user, asset);
            if (balance == 0) {
                continue;
            }

            // Withdraw asset from CrashGuardCore to this contract
            try crashGuardCore.emergencyWithdraw(user, asset, balance) {
                // Execute swap through DEX aggregator
                try
                    dexAggregator.swapTokens(
                        asset,
                        targetStable,
                        balance,
                        maxSlippage,
                        block.timestamp + DEFAULT_DEADLINE
                    )
                returns (uint256 amountOut, uint256 actualSlippage) {
                    totalConverted += amountOut;
                    totalSlippage += actualSlippage;
                    successfulConversions++;

                    // Deposit converted stablecoin back to user's portfolio
                    IERC20(targetStable).forceApprove(
                        address(crashGuardCore),
                        amountOut
                    );
                    // Note: This would require a deposit function that accepts deposits on behalf of users
                    // For now, we'll transfer to the user directly
                    IERC20(targetStable).safeTransfer(user, amountOut);
                } catch {
                    // Swap failed, return asset to user
                    IERC20(asset).safeTransfer(user, balance);
                }
            } catch {
                // Withdrawal failed, continue with next asset
                continue;
            }
        }

        if (successfulConversions == 0) {
            return
                ExecutionResult({
                    success: false,
                    amountConverted: 0,
                    actualSlippage: 0,
                    errorMessage: "No conversions successful"
                });
        }

        uint256 avgSlippage = totalSlippage / successfulConversions;

        return
            ExecutionResult({
                success: true,
                amountConverted: totalConverted,
                actualSlippage: avgSlippage,
                errorMessage: ""
            });
    }

    /**
     * @dev Internal function to execute emergency protection logic
     * @param user User address to protect
     * @return ExecutionResult with operation details
     */
    function _executeEmergencyProtectionInternal(
        address user
    ) internal returns (ExecutionResult memory) {
        // Get user's portfolio
        ICrashGuardCore.Portfolio memory portfolio = crashGuardCore
            .getUserPortfolio(user);
        require(portfolio.assets.length > 0, "No assets to protect");

        // Get user's protection policy
        ICrashGuardCore.ProtectionPolicy memory policy = crashGuardCore
            .getProtectionPolicy(user);
        require(
            policy.stablecoinPreference != address(0),
            "No stablecoin preference set"
        );

        // Prepare assets for conversion
        address[] memory assetsToConvert = new address[](
            portfolio.assets.length
        );
        uint256 assetCount = 0;

        for (uint256 i = 0; i < portfolio.assets.length; i++) {
            ICrashGuardCore.Asset memory asset = portfolio.assets[i];
            // Only convert risky assets (risk level > 2) or if total portfolio risk is high
            if (asset.riskLevel > 2 || portfolio.riskScore > 7000) {
                // 70% risk threshold
                assetsToConvert[assetCount] = asset.tokenAddress;
                assetCount++;
            }
        }

        if (assetCount == 0) {
            return
                ExecutionResult({
                    success: false,
                    amountConverted: 0,
                    actualSlippage: 0,
                    errorMessage: "No risky assets to convert"
                });
        }

        // Resize array to actual count
        address[] memory finalAssets = new address[](assetCount);
        for (uint256 i = 0; i < assetCount; i++) {
            finalAssets[i] = assetsToConvert[i];
        }

        // Execute conversion
        ExecutionResult memory result = _executeConversion(
            user,
            finalAssets,
            policy.stablecoinPreference,
            policy.maxSlippage
        );

        // Update execution tracking
        userLastExecution[user] = block.timestamp;
        userExecutionCount[user]++;
        totalExecutions++;

        if (result.success) {
            successfulExecutions++;
        }

        emit EmergencyExecutionCompleted(user, result);
        return result;
    }

    /**
     * @dev Execute emergency protection triggered by Lit Action
     * @param user User address to protect
     * @param litActionId Lit Action ID that triggered this execution
     * @param executionData Additional execution data from Lit Action
     * @return ExecutionResult with operation details
     */
    function executeLitActionTriggeredProtection(
        address user,
        string calldata litActionId,
        bytes calldata executionData
    ) external nonReentrant notPaused returns (ExecutionResult memory) {
        require(user != address(0), "Invalid user address");
        require(authorizedLitActions[litActionId], "Lit Action not authorized");

        // Verify Lit Action authorization through integration contract
        if (address(litProtocolIntegration) != address(0)) {
            require(
                litProtocolIntegration.isAuthorizedByLitAction(
                    user,
                    litActionId,
                    executionData
                ),
                "Not authorized by Lit Action"
            );
        }

        // Verify Lit Action is active in relay contract
        if (address(litRelayContract) != address(0)) {
            (bool active, ) = litRelayContract.getLitActionStatus(litActionId);
            require(active, "Lit Action not active");
        }

        emit EmergencyExecutionStarted(user, block.timestamp);

        // Process the execution hash in CrashGuardCore
        bytes32 executionHash = keccak256(
            abi.encodePacked(user, litActionId, executionData, block.timestamp)
        );

        // Notify CrashGuardCore about the Lit Action execution
        crashGuardCore.processLitActionExecution(
            user,
            executionHash,
            litActionId
        );

        // Execute standard emergency protection logic
        return _executeEmergencyProtectionInternal(user);
    }

    /**
     * @dev Authorize Lit Action for emergency execution
     * @param litActionId Lit Action ID to authorize
     */
    function authorizeLitAction(
        string calldata litActionId
    ) external onlyOwner {
        require(bytes(litActionId).length > 0, "Invalid Lit Action ID");

        // Verify Lit Action exists in relay contract
        if (address(litRelayContract) != address(0)) {
            (bool active, ) = litRelayContract.getLitActionStatus(litActionId);
            require(active, "Lit Action not found in relay");
        }

        authorizedLitActions[litActionId] = true;
    }

    /**
     * @dev Revoke Lit Action authorization
     * @param litActionId Lit Action ID to revoke
     */
    function revokeLitActionAuthorization(
        string calldata litActionId
    ) external onlyOwner {
        authorizedLitActions[litActionId] = false;
    }

    /**
     * @dev Set Lit Protocol integration contract
     * @param _litProtocolIntegration Lit Protocol integration contract address
     */
    function setLitProtocolIntegration(
        address _litProtocolIntegration
    ) external onlyOwner {
        require(_litProtocolIntegration != address(0), "Invalid address");
        litProtocolIntegration = ILitProtocolIntegration(
            _litProtocolIntegration
        );
    }

    /**
     * @dev Set Lit Relay contract
     * @param _litRelayContract Lit Relay contract address
     */
    function setLitRelayContract(address _litRelayContract) external onlyOwner {
        require(_litRelayContract != address(0), "Invalid address");
        litRelayContract = ILitRelayContract(_litRelayContract);
    }

    /**
     * @dev Check if Lit Action is authorized
     * @param litActionId Lit Action ID to check
     * @return bool True if authorized
     */
    function isLitActionAuthorized(
        string calldata litActionId
    ) external view returns (bool) {
        return authorizedLitActions[litActionId];
    }

    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Token address to recover
     * @param amount Amount to recover
     */
    function emergencyRecoverToken(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /**
     * @dev Receive ETH for emergency operations
     */
    receive() external payable {
        // Allow contract to receive ETH for gas and operations
    }
}
