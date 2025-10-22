// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ICrashGuardCore.sol";
import "./interfaces/ILitProtocolIntegration.sol";
import "./interfaces/ILitRelayContract.sol";

// Interface for ERC20 metadata (optional extension)
interface IERC20Metadata {
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract CrashGuardCore is ICrashGuardCore, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Custom errors for gas efficiency
    error TokenBlacklisted();
    error TokenNotSupported();
    error OnlyEmergencyExecutor();
    error UserNotPKPAuthorized();
    error NotAuthorizedByLitAction();
    error UnauthorizedBridge();
    error DepositAlreadyProcessed();
    error InvalidUserAddress();
    error MinimumStablecoinRequired();
    error MinimumTokenRequired();
    error ETHAmountMismatch();
    error ETHNotExpectedForERC20();
    error AmountMustBePositive();
    error InsufficientBalance();
    error ETHTransferFailed();
    error InvalidCrashThreshold();
    error MaxSlippageExceeded();
    error InvalidStablecoin();
    error StablecoinNotRegistered();
    error GasLimitTooLow();
    error InvalidTokenAddress();
    error CannotRemoveETH();
    error InvalidAddress();
    error InvalidPKPAddress();
    error InvalidLitActionID();
    error PKPNotRegistered();
    error PKPAddressMismatch();
    error PKPNotActive();
    error NotAuthorized();
    error ExecutionAlreadyProcessed();
    error LitActionIDMismatch();
    error IndexOutOfBounds();
    error TokenNotSupportedForStatus();
    error InvalidBridgeAddress();

    // User portfolios mapping
    mapping(address => Portfolio) private userPortfolios;
    mapping(address => ProtectionPolicy) private userPolicies;
    mapping(address => mapping(address => uint256)) private userBalances;

    // Supported tokens mapping (optional - for enhanced features)
    mapping(address => bool) public supportedTokens;

    // Permissionless mode - allows any token deposits
    bool public permissionlessMode = true;

    // Blacklisted tokens (for security)
    mapping(address => bool) public blacklistedTokens;

    // Emergency executor address
    address public emergencyExecutor;

    // Lit Protocol integration
    ILitProtocolIntegration public litProtocolIntegration;
    ILitRelayContract public litRelayContract;

    // Cross-chain bridge support
    mapping(address => bool) public authorizedBridges;
    mapping(bytes32 => bool) public processedCrossChainDeposits;

    // PKP-based operations
    mapping(address => bool) public pkpAuthorizedUsers;
    mapping(address => string) public userLitActions;
    mapping(bytes32 => bool) public processedLitActionExecutions;

    // Constants - configurable from client side
    uint256 public constant MAX_SLIPPAGE_LIMIT = 5000; // 50% absolute max
    uint256 public constant MIN_STABLECOIN_DEPOSIT = 1e6; // 1 USDC/USDT (6 decimals)
    uint256 public constant MIN_TOKEN_DEPOSIT = 1e16; // 0.01 tokens (18 decimals)

    // Stablecoin registry
    mapping(address => bool) public isStablecoin;

    modifier onlyEmergencyExecutor() {
        if (msg.sender != emergencyExecutor) revert OnlyEmergencyExecutor();
        _;
    }

    modifier validToken(address token) {
        if (permissionlessMode) {
            if (blacklistedTokens[token]) revert TokenBlacklisted();
        } else {
            if (!supportedTokens[token]) revert TokenNotSupported();
        }
        _;
    }

    modifier onlyPKPAuthorized(address user) {
        if (!pkpAuthorizedUsers[user]) revert UserNotPKPAuthorized();
        _;
    }

    modifier onlyLitAction(string memory actionId) {
        if (
            address(litProtocolIntegration) == address(0) ||
            !litProtocolIntegration.isAuthorizedByLitAction(
                msg.sender,
                actionId,
                ""
            )
        ) revert NotAuthorizedByLitAction();
        _;
    }

    constructor() {
        // ETH is always supported (represented as address(0))
        supportedTokens[address(0)] = true;

        // Start in permissionless mode
        permissionlessMode = true;
    }

    function depositAsset(
        address token,
        uint256 amount
    ) external payable nonReentrant validToken(token) {
        _processDeposit(msg.sender, token, amount);
    }

    /**
     * @dev Cross-chain deposit function
     * @param user User address on destination chain
     * @param token Token address
     * @param amount Amount to deposit
     * @param sourceChain Source chain identifier
     * @param depositHash Unique deposit hash from source chain
     */
    function crossChainDeposit(
        address user,
        address token,
        uint256 amount,
        uint256 sourceChain,
        bytes32 depositHash
    ) external nonReentrant validToken(token) {
        if (!authorizedBridges[msg.sender]) revert UnauthorizedBridge();
        if (processedCrossChainDeposits[depositHash])
            revert DepositAlreadyProcessed();
        if (user == address(0)) revert InvalidUserAddress();

        // Mark as processed to prevent replay
        processedCrossChainDeposits[depositHash] = true;

        // Process the deposit for the user
        _processDepositInternal(user, token, amount);

        emit CrossChainDepositProcessed(
            user,
            token,
            amount,
            sourceChain,
            depositHash
        );
    }

    /**
     * @dev Internal deposit processing
     * @param user User address
     * @param token Token address
     * @param amount Amount to deposit
     */
    function _processDeposit(
        address user,
        address token,
        uint256 amount
    ) private {
        // Auto-detect stablecoin if not set (basic heuristic)
        if (!isStablecoin[token] && !supportedTokens[token]) {
            _autoDetectStablecoin(token);
        }

        // Check minimum deposit based on token type
        if (isStablecoin[token]) {
            if (amount < MIN_STABLECOIN_DEPOSIT)
                revert MinimumStablecoinRequired();
        } else {
            if (amount < MIN_TOKEN_DEPOSIT) revert MinimumTokenRequired();
        }

        if (token == address(0)) {
            // ETH deposit
            if (msg.value != amount) revert ETHAmountMismatch();
        } else {
            // ERC20 deposit
            if (msg.value != 0) revert ETHNotExpectedForERC20();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        _processDepositInternal(user, token, amount);
    }

    /**
     * @dev Internal deposit processing (shared by regular and cross-chain deposits)
     * @param user User address
     * @param token Token address
     * @param amount Amount to deposit
     */
    function _processDepositInternal(
        address user,
        address token,
        uint256 amount
    ) private {
        // Update user balance
        userBalances[user][token] += amount;

        // Update portfolio
        _updatePortfolio(user, token, amount, true);

        emit AssetDeposited(user, token, amount);
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
        if (amount == 0) revert AmountMustBePositive();
        if (userBalances[msg.sender][token] < amount)
            revert InsufficientBalance();

        // Update user balance
        userBalances[msg.sender][token] -= amount;

        // Update portfolio
        _updatePortfolio(msg.sender, token, amount, false);

        // Transfer assets
        if (token == address(0)) {
            // ETH withdrawal
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) revert ETHTransferFailed();
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
     * @dev Set protection policy for user - client configurable
     * @param policy Protection policy configuration
     */
    function setProtectionPolicy(ProtectionPolicy memory policy) external {
        if (policy.crashThreshold == 0 || policy.crashThreshold > 10000) {
            revert InvalidCrashThreshold();
        }
        if (policy.maxSlippage > MAX_SLIPPAGE_LIMIT) {
            revert MaxSlippageExceeded();
        }
        if (policy.stablecoinPreference == address(0)) {
            revert InvalidStablecoin();
        }
        if (!isStablecoin[policy.stablecoinPreference]) {
            revert StablecoinNotRegistered();
        }
        if (policy.gasLimit < 21000) revert GasLimitTooLow();

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
     * @dev Add supported token (optional in permissionless mode)
     * @param token Token address to add
     * @param _isStablecoin Whether token is a stablecoin
     */
    function addSupportedToken(
        address token,
        bool _isStablecoin
    ) external onlyOwner {
        if (token == address(0)) revert InvalidTokenAddress();
        supportedTokens[token] = true;
        isStablecoin[token] = _isStablecoin;
    }

    /**
     * @dev Toggle permissionless mode
     * @param _permissionless True to enable permissionless deposits
     */
    function setPermissionlessMode(bool _permissionless) external onlyOwner {
        permissionlessMode = _permissionless;
        emit PermissionlessModeUpdated(_permissionless);
    }

    /**
     * @dev Blacklist a token (security measure)
     * @param token Token address to blacklist
     * @param blacklisted True to blacklist, false to remove from blacklist
     */
    function setTokenBlacklist(
        address token,
        bool blacklisted
    ) external onlyOwner {
        blacklistedTokens[token] = blacklisted;
        emit TokenBlacklistUpdated(token, blacklisted);
    }

    /**
     * @dev Authorize bridge for cross-chain deposits
     * @param bridge Bridge contract address
     * @param authorized True to authorize, false to revoke
     */
    function setAuthorizedBridge(
        address bridge,
        bool authorized
    ) external onlyOwner {
        if (bridge == address(0)) revert InvalidBridgeAddress();
        authorizedBridges[bridge] = authorized;
        emit BridgeAuthorizationUpdated(bridge, authorized);
    }

    /**
     * @dev Remove supported token
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert CannotRemoveETH();
        supportedTokens[token] = false;
        isStablecoin[token] = false;
    }

    /**
     * @dev Update stablecoin status
     * @param token Token address
     * @param _isStablecoin Stablecoin status
     */
    function setStablecoinStatus(
        address token,
        bool _isStablecoin
    ) external onlyOwner {
        require(supportedTokens[token], "Token not supported");
        isStablecoin[token] = _isStablecoin;
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
    )
        external
        payable
        nonReentrant
        validToken(token)
        onlyLitAction(litActionId)
    {
        require(user != address(0), "Invalid user address");
        // Check minimum deposit based on token type
        if (isStablecoin[token]) {
            require(
                amount >= MIN_STABLECOIN_DEPOSIT,
                "Minimum 1 stablecoin required"
            );
        } else {
            require(
                amount >= MIN_TOKEN_DEPOSIT,
                "Minimum 0.01 tokens required"
            );
        }
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
            (bool success, ) = payable(emergencyExecutor).call{value: amount}(
                ""
            );
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
            require(
                litRelayContract.isPKPRegistered(pkpAddress),
                "PKP not registered"
            );
        }

        // Verify user has PKP authentication
        if (address(litProtocolIntegration) != address(0)) {
            ILitProtocolIntegration.PKPAuth
                memory pkpAuth = litProtocolIntegration.getUserPKP(user);
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
        require(
            !processedLitActionExecutions[executionHash],
            "Execution already processed"
        );
        require(pkpAuthorizedUsers[user], "User not PKP authorized");
        require(
            keccak256(bytes(userLitActions[user])) ==
                keccak256(bytes(litActionId)),
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
     * @dev Auto-detect if token is a stablecoin (basic heuristic)
     * @param token Token address
     */
    function _autoDetectStablecoin(address token) private {
        try IERC20Metadata(token).symbol() returns (string memory symbol) {
            bytes32 symbolHash = keccak256(bytes(symbol));

            // Common stablecoin symbols
            if (
                symbolHash == keccak256("USDC") ||
                symbolHash == keccak256("USDT") ||
                symbolHash == keccak256("DAI") ||
                symbolHash == keccak256("BUSD") ||
                symbolHash == keccak256("FRAX") ||
                symbolHash == keccak256("TUSD") ||
                symbolHash == keccak256("USDP")
            ) {
                isStablecoin[token] = true;
                emit StablecoinAutoDetected(token, symbol);
            }
        } catch {
            // If symbol() fails, assume it's not a stablecoin
        }
    }

    /**
     * @dev Check if token is supported (permissionless or whitelisted)
     * @param token Token address
     * @return bool True if token can be deposited
     */
    function isTokenSupported(address token) external view returns (bool) {
        if (permissionlessMode) {
            return !blacklistedTokens[token];
        } else {
            return supportedTokens[token];
        }
    }

    /**
     * @dev Get token info
     * @param token Token address
     * @return supported Whether token is supported
     * @return stablecoin Whether token is a stablecoin
     * @return blacklisted Whether token is blacklisted
     */
    function getTokenInfo(
        address token
    )
        external
        view
        returns (bool supported, bool stablecoin, bool blacklisted)
    {
        if (permissionlessMode) {
            supported = !blacklistedTokens[token];
        } else {
            supported = supportedTokens[token];
        }
        stablecoin = isStablecoin[token];
        blacklisted = blacklistedTokens[token];
    }

    /**
     * @dev Get user's associated Lit Action ID
     * @param user User address
     * @return string Lit Action ID
     */
    function getUserLitAction(
        address user
    ) external view returns (string memory) {
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
