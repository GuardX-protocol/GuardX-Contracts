// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ICrashGuardCore.sol";
import "./interfaces/ILitProtocolIntegration.sol";
import "./interfaces/ILitRelayContract.sol";

contract CrashGuardCore is ICrashGuardCore, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // User portfolios mapping
    mapping(address => Portfolio) private userPortfolios;
    mapping(address => ProtectionPolicy) private userPolicies;
    mapping(address => mapping(address => uint256)) private userBalances;

    // Supported tokens mapping
    mapping(address => bool) public supportedTokens;

    // Emergency executor address
    address public emergencyExecutor;

    // Lit Protocol integration
    ILitProtocolIntegration public litProtocolIntegration;
    ILitRelayContract public litRelayContract;
    
    // PKP-based operations
    mapping(address => bool) public pkpAuthorizedUsers;
    mapping(address => string) public userLitActions;
    mapping(bytes32 => bool) public processedLitActionExecutions;

    // Constants
    uint256 private constant MAX_SLIPPAGE = 5000; // 50% max slippage
    uint256 private constant MIN_DEPOSIT = 1e15; // 0.001 ETH minimum

    modifier onlyEmergencyExecutor() {
        require(msg.sender == emergencyExecutor, "Only emergency executor");
        _;
    }

    modifier validToken(address token) {
        require(supportedTokens[token], "Token not supported");
        _;
    }

    modifier onlyPKPAuthorized(address user) {
        require(pkpAuthorizedUsers[user], "User not PKP authorized");
        _;
    }

    modifier onlyLitAction(string memory actionId) {
        require(
            address(litProtocolIntegration) != address(0) &&
            litProtocolIntegration.isAuthorizedByLitAction(msg.sender, actionId, ""),
            "Not authorized by Lit Action"
        );
        _;
    }

    constructor() {
        // ETH is always supported (represented as address(0))
        supportedTokens[address(0)] = true;
    }

    function depositAsset(
        address token,
        uint256 amount
    ) external payable nonReentrant validToken(token) {
        require(amount >= MIN_DEPOSIT, "Amount below minimum");

        if (token == address(0)) {
            // ETH deposit
            require(msg.value == amount, "ETH amount mismatch");
        } else {
            // ERC20 deposit
            require(msg.value == 0, "ETH not expected for ERC20");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Update user balance
        userBalances[msg.sender][token] += amount;

        // Update portfolio
        _updatePortfolio(msg.sender, token, amount, true);

        emit AssetDeposited(msg.sender, token, amount);
    }

    /**
     * @dev Withdraw assets from the protection system
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function withdrawAsset(
        address token,
        uint256 amount
    ) external nonReentrant validToken(token) {
        require(amount > 0, "Amount must be positive");
        require(
            userBalances[msg.sender][token] >= amount,
            "Insufficient balance"
        );

        // Update user balance
        userBalances[msg.sender][token] -= amount;

        // Update portfolio
        _updatePortfolio(msg.sender, token, amount, false);

        // Transfer assets
        if (token == address(0)) {
            // ETH withdrawal
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 withdrawal
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit AssetWithdrawn(msg.sender, token, amount);
    }

    /**
     * @dev Get user's portfolio information
     * @param user User address
     * @return Portfolio struct with user's assets
     */
    function getUserPortfolio(
        address user
    ) external view returns (Portfolio memory) {
        return userPortfolios[user];
    }

    /**
     * @dev Set protection policy for user
     * @param policy Protection policy configuration
     */
    function setProtectionPolicy(ProtectionPolicy memory policy) external {
        require(
            policy.crashThreshold > 0 && policy.crashThreshold <= 10000,
            "Invalid crash threshold"
        );
        require(policy.maxSlippage <= MAX_SLIPPAGE, "Slippage too high");
        require(
            policy.stablecoinPreference != address(0),
            "Invalid stablecoin"
        );
        require(policy.gasLimit >= 21000, "Gas limit too low");

        userPolicies[msg.sender] = policy;

        emit PolicyUpdated(msg.sender, policy);
    }

    /**
     * @dev Get user's protection policy
     * @param user User address
     * @return ProtectionPolicy struct
     */
    function getProtectionPolicy(
        address user
    ) external view returns (ProtectionPolicy memory) {
        return userPolicies[user];
    }

    /**
     * @dev Get user's balance for a specific token
     * @param user User address
     * @param token Token address
     * @return Balance amount
     */
    function getUserBalance(
        address user,
        address token
    ) external view returns (uint256) {
        return userBalances[user][token];
    }

    /**
     * @dev Emergency withdrawal by emergency executor
     * @param user User address
     * @param token Token address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address user,
        address token,
        uint256 amount
    ) external onlyEmergencyExecutor nonReentrant {
        require(userBalances[user][token] >= amount, "Insufficient balance");

        userBalances[user][token] -= amount;
        _updatePortfolio(user, token, amount, false);

        if (token == address(0)) {
            (bool success, ) = payable(emergencyExecutor).call{value: amount}(
                ""
            );
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(emergencyExecutor, amount);
        }

        emit EmergencyProtectionTriggered(user, block.timestamp);
    }

    /**
     * @dev Add supported token
     * @param token Token address to add
     */
    function addSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        supportedTokens[token] = true;
    }

    /**
     * @dev Remove supported token
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Cannot remove ETH");
        supportedTokens[token] = false;
    }

    /**
     * @dev Set emergency executor address
     * @param _emergencyExecutor New emergency executor address
     */
    function setEmergencyExecutor(
        address _emergencyExecutor
    ) external onlyOwner {
        require(_emergencyExecutor != address(0), "Invalid address");
        emergencyExecutor = _emergencyExecutor;
    }

    /**
     * @dev Internal function to update user portfolio
     * @param user User address
     * @param token Token address
     * @param amount Amount changed
     * @param isDeposit True for deposit, false for withdrawal
     */
    function _updatePortfolio(
        address user,
        address token,
        uint256 amount,
        bool isDeposit
    ) private {
        Portfolio storage portfolio = userPortfolios[user];

        // Find existing asset or create new one
        bool found = false;
        for (uint256 i = 0; i < portfolio.assets.length; i++) {
            if (portfolio.assets[i].tokenAddress == token) {
                if (isDeposit) {
                    portfolio.assets[i].amount += amount;
                } else {
                    portfolio.assets[i].amount -= amount;
                    // Remove asset if balance is zero
                    if (portfolio.assets[i].amount == 0) {
                        _removeAssetFromPortfolio(portfolio, i);
                    }
                }
                found = true;
                break;
            }
        }

        // Add new asset if not found and is deposit
        if (!found && isDeposit) {
            portfolio.assets.push(
                Asset({
                    tokenAddress: token,
                    amount: amount,
                    valueUSD: 0, // Will be updated by price oracle
                    riskLevel: 1 // Default risk level
                })
            );
        }

        portfolio.lastUpdated = block.timestamp;
        // Total value and risk score will be updated by monitoring service
    }

    /**
     * @dev Remove asset from portfolio array
     * @param portfolio Portfolio reference
     * @param index Index to remove
     */
    function _removeAssetFromPortfolio(
        Portfolio storage portfolio,
        uint256 index
    ) private {
        require(index < portfolio.assets.length, "Index out of bounds");

        // Move last element to deleted spot and remove last element
        portfolio.assets[index] = portfolio.assets[portfolio.assets.length - 1];
        portfolio.assets.pop();
    }

    /**
     * @dev Update portfolio values (called by price oracle)
     * @param user User address
     * @param totalValue New total portfolio value
     * @param riskScore New risk score
     */
    function updatePortfolioValue(
        address user,
        uint256 totalValue,
        uint256 riskScore
    ) external onlyOwner {
        Portfolio storage portfolio = userPortfolios[user];
        portfolio.totalValue = totalValue;
        portfolio.riskScore = riskScore;
        portfolio.lastUpdated = block.timestamp;
    }

    /**
     * @dev Update individual asset value and risk
     * @param user User address
     * @param token Token address
     * @param valueUSD New USD value
     * @param riskLevel New risk level
     */
    function updateAssetValue(
        address user,
        address token,
        uint256 valueUSD,
        uint8 riskLevel
    ) external onlyOwner {
        Portfolio storage portfolio = userPortfolios[user];

        for (uint256 i = 0; i < portfolio.assets.length; i++) {
            if (portfolio.assets[i].tokenAddress == token) {
                portfolio.assets[i].valueUSD = valueUSD;
                portfolio.assets[i].riskLevel = riskLevel;
                break;
            }
        }

        portfolio.lastUpdated = block.timestamp;
    }

    /**
     * @dev PKP-based deposit function for automated operations
     * @param user User address on whose behalf to deposit
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to deposit
     * @param litActionId Lit Action ID authorizing this operation
     */
    function pkpDepositAsset(
        address user,
        address token,
        uint256 amount,
        string calldata litActionId
    ) external payable nonReentrant validToken(token) onlyLitAction(litActionId) {
        require(user != address(0), "Invalid user address");
        require(amount >= MIN_DEPOSIT, "Amount below minimum");
        require(pkpAuthorizedUsers[user], "User not PKP authorized");

        if (token == address(0)) {
            // ETH deposit
            require(msg.value == amount, "ETH amount mismatch");
        } else {
            // ERC20 deposit - requires prior approval
            require(msg.value == 0, "ETH not expected for ERC20");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Update user balance
        userBalances[user][token] += amount;

        // Update portfolio
        _updatePortfolio(user, token, amount, true);

        emit AssetDeposited(user, token, amount);
    }

    /**
     * @dev PKP-based withdrawal for automated emergency operations
     * @param user User address
     * @param token Token address
     * @param amount Amount to withdraw
     * @param litActionId Lit Action ID authorizing this operation
     */
    function pkpWithdrawAsset(
        address user,
        address token,
        uint256 amount,
        string calldata litActionId
    ) external nonReentrant validToken(token) onlyLitAction(litActionId) {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Amount must be positive");
        require(pkpAuthorizedUsers[user], "User not PKP authorized");
        require(userBalances[user][token] >= amount, "Insufficient balance");

        // Update user balance
        userBalances[user][token] -= amount;

        // Update portfolio
        _updatePortfolio(user, token, amount, false);

        // Transfer assets to the Lit Action executor (emergency executor)
        if (token == address(0)) {
            // ETH withdrawal
            (bool success, ) = payable(emergencyExecutor).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 withdrawal
            IERC20(token).safeTransfer(emergencyExecutor, amount);
        }

        emit AssetWithdrawn(user, token, amount);
    }

    /**
     * @dev Set up PKP authorization for user
     * @param user User address
     * @param pkpAddress PKP address
     * @param litActionId Associated Lit Action ID
     */
    function setupPKPAuthorization(
        address user,
        address pkpAddress,
        string calldata litActionId
    ) external {
        require(user == msg.sender || msg.sender == owner(), "Not authorized");
        require(pkpAddress != address(0), "Invalid PKP address");
        require(bytes(litActionId).length > 0, "Invalid Lit Action ID");

        // Verify PKP is registered with Lit Protocol
        if (address(litRelayContract) != address(0)) {
            require(litRelayContract.isPKPRegistered(pkpAddress), "PKP not registered");
        }

        // Verify user has PKP authentication
        if (address(litProtocolIntegration) != address(0)) {
            ILitProtocolIntegration.PKPAuth memory pkpAuth = litProtocolIntegration.getUserPKP(user);
            require(pkpAuth.pkpAddress == pkpAddress, "PKP address mismatch");
            require(pkpAuth.isActive, "PKP not active");
        }

        pkpAuthorizedUsers[user] = true;
        userLitActions[user] = litActionId;
    }

    /**
     * @dev Revoke PKP authorization for user
     * @param user User address
     */
    function revokePKPAuthorization(address user) external {
        require(user == msg.sender || msg.sender == owner(), "Not authorized");
        pkpAuthorizedUsers[user] = false;
        delete userLitActions[user];
    }

    /**
     * @dev Set Lit Protocol integration contract
     * @param _litProtocolIntegration Lit Protocol integration contract address
     */
    function setLitProtocolIntegration(address _litProtocolIntegration) external onlyOwner {
        require(_litProtocolIntegration != address(0), "Invalid address");
        litProtocolIntegration = ILitProtocolIntegration(_litProtocolIntegration);
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
     * @dev Process Lit Action execution for emergency operations
     * @param user User address
     * @param executionHash Hash of the execution data
     * @param litActionId Lit Action ID
     */
    function processLitActionExecution(
        address user,
        bytes32 executionHash,
        string calldata litActionId
    ) external onlyEmergencyExecutor {
        require(!processedLitActionExecutions[executionHash], "Execution already processed");
        require(pkpAuthorizedUsers[user], "User not PKP authorized");
        require(
            keccak256(bytes(userLitActions[user])) == keccak256(bytes(litActionId)),
            "Lit Action ID mismatch"
        );

        processedLitActionExecutions[executionHash] = true;
        
        // Trigger emergency protection for the user
        emit EmergencyProtectionTriggered(user, block.timestamp);
    }

    /**
     * @dev Check if user is PKP authorized
     * @param user User address
     * @return bool True if user is PKP authorized
     */
    function isPKPAuthorized(address user) external view returns (bool) {
        return pkpAuthorizedUsers[user];
    }

    /**
     * @dev Get user's associated Lit Action ID
     * @param user User address
     * @return string Lit Action ID
     */
    function getUserLitAction(address user) external view returns (string memory) {
        return userLitActions[user];
    }

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        // Implementation would pause contract operations
        // This is a placeholder for emergency controls
    }

    /**
     * @dev Get total number of users
     * @return Number of users with portfolios
     */
    function getTotalUsers() external view returns (uint256) {
        // This would require additional tracking in a real implementation
        return 0; // Placeholder
    }

    receive() external payable {
        // Allow contract to receive ETH
        revert("Use depositAsset function");
    }
}
