// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/ICrossChainManager.sol";
import "./interfaces/ILitRelayContract.sol";
import "./interfaces/ILitProtocolIntegration.sol";

contract CrossChainManager is ICrossChainManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;


    // Core contracts
    ILitRelayContract public litRelayContract;
    ILitProtocolIntegration public litProtocolIntegration;

    // Cross-chain state
    mapping(address => CrossChainPortfolio) public userPortfolios;
    mapping(bytes32 => CrossChainAsset) public lockedAssets;
    mapping(bytes32 => AssetMigration) public migrations;
    mapping(address => bytes32[]) public userLockHashes;
    mapping(address => bytes32[]) public userMigrationHashes;

    // Chain configuration
    mapping(uint256 => bool) public supportedChains;
    mapping(uint256 => address) public chainContracts; // Contract addresses on each chain
    mapping(uint256 => bool) public chainActive;
    uint256[] public supportedChainsList;

    // Cross-chain messaging
    mapping(bytes32 => bool) public processedMessages;
    mapping(uint256 => uint256) public chainNonces;

    // Access control
    mapping(address => bool) public authorizedRelayers;
    mapping(address => bool) public emergencyCoordinators;

    // Constants
    uint256 public constant LOCK_TIMEOUT = 1 hours;
    uint256 public constant MIGRATION_TIMEOUT = 2 hours;
    uint256 public constant MAX_SUPPORTED_CHAINS = 10;
    uint256 public immutable CURRENT_CHAIN_ID;

    modifier onlyAuthorizedRelayer() {
        require(
            authorizedRelayers[msg.sender] || msg.sender == owner(),
            "Not authorized relayer"
        );
        _;
    }

    modifier onlyEmergencyCoordinator() {
        require(
            emergencyCoordinators[msg.sender] || msg.sender == owner(),
            "Not emergency coordinator"
        );
        _;
    }

    modifier validChain(uint256 chainId) {
        require(supportedChains[chainId], "Chain not supported");
        require(chainActive[chainId], "Chain not active");
        _;
    }

    modifier validUser(address user) {
        require(user != address(0), "Invalid user address");
        _;
    }

    constructor(
        address _litRelayContract,
        address _litProtocolIntegration
    ) {
        require(_litRelayContract != address(0), "Invalid Lit Relay Contract");
        require(_litProtocolIntegration != address(0), "Invalid Lit Protocol Integration");

        litRelayContract = ILitRelayContract(_litRelayContract);
        litProtocolIntegration = ILitProtocolIntegration(_litProtocolIntegration);
        CURRENT_CHAIN_ID = block.chainid;

        // Initialize with current chain
        supportedChains[CURRENT_CHAIN_ID] = true;
        chainActive[CURRENT_CHAIN_ID] = true;
        chainContracts[CURRENT_CHAIN_ID] = address(this);
        supportedChainsList.push(CURRENT_CHAIN_ID);

        authorizedRelayers[msg.sender] = true;
        emergencyCoordinators[msg.sender] = true;
    }

    function lockAsset(
        address user,
        address token,
        uint256 amount,
        uint256 targetChainId
    ) external override onlyAuthorizedRelayer validUser(user) validChain(targetChainId) returns (bytes32) {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be positive");
        require(targetChainId != CURRENT_CHAIN_ID, "Cannot lock for same chain");

        // Generate lock hash
        bytes32 lockHash = keccak256(
            abi.encodePacked(
                user,
                token,
                amount,
                CURRENT_CHAIN_ID,
                targetChainId,
                block.timestamp,
                chainNonces[targetChainId]++
            )
        );

        // Transfer tokens to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Create locked asset
        CrossChainAsset memory lockedAsset = CrossChainAsset({
            tokenAddress: token,
            amount: amount,
            chainId: CURRENT_CHAIN_ID,
            isLocked: true,
            lockTimestamp: block.timestamp,
            lockHash: lockHash
        });

        lockedAssets[lockHash] = lockedAsset;
        userLockHashes[user].push(lockHash);

        // Update user's cross-chain portfolio
        _updateCrossChainPortfolio(user, token, amount, CURRENT_CHAIN_ID, true);

        emit AssetLocked(user, token, amount, CURRENT_CHAIN_ID, lockHash);
        return lockHash;
    }

    /**
     * @dev Unlock asset with PKP signature
     * @param user User address
     * @param lockHash Hash of the locked asset
     * @param signature PKP signature authorizing unlock
     * @return bool True if successful
     */
    function unlockAsset(
        address user,
        bytes32 lockHash,
        bytes calldata signature
    ) external override onlyAuthorizedRelayer validUser(user) nonReentrant returns (bool) {
        CrossChainAsset storage asset = lockedAssets[lockHash];
        require(asset.isLocked, "Asset not locked");
        require(asset.lockHash == lockHash, "Invalid lock hash");
        require(
            block.timestamp <= asset.lockTimestamp + LOCK_TIMEOUT,
            "Lock expired"
        );

        bytes32 unlockHash = keccak256(
            abi.encodePacked(user, lockHash, block.timestamp)
        );
        
        ILitRelayContract.PKPSignature memory pkpSig = ILitRelayContract.PKPSignature({
            signature: signature,
            pkpAddress: _getUserPKPAddress(user),
            timestamp: block.timestamp,
            messageHash: unlockHash
        });

        require(
            litRelayContract.verifyPKPSignature(pkpSig, unlockHash),
            "Invalid PKP signature"
        );

        asset.isLocked = false;

        IERC20(asset.tokenAddress).safeTransfer(msg.sender, asset.amount);

        _updateCrossChainPortfolio(user, asset.tokenAddress, asset.amount, asset.chainId, false);

        emit AssetUnlocked(user, asset.tokenAddress, asset.amount, asset.chainId, lockHash);
        return true;
    }

    function initiateCrossChainMigration(
        address user,
        address token,
        uint256 amount,
        uint256 targetChainId
    ) external override onlyAuthorizedRelayer validUser(user) validChain(targetChainId) returns (bytes32) {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be positive");
        require(targetChainId != CURRENT_CHAIN_ID, "Cannot migrate to same chain");

        // Generate migration hash
        bytes32 migrationHash = keccak256(
            abi.encodePacked(
                user,
                token,
                amount,
                CURRENT_CHAIN_ID,
                targetChainId,
                block.timestamp,
                chainNonces[targetChainId]++
            )
        );

        bytes32 lockHash = this.lockAsset(user, token, amount, targetChainId);

        AssetMigration memory migration = AssetMigration({
            user: user,
            tokenAddress: token,
            amount: amount,
            sourceChainId: CURRENT_CHAIN_ID,
            targetChainId: targetChainId,
            migrationHash: migrationHash,
            timestamp: block.timestamp,
            completed: false
        });

        migrations[migrationHash] = migration;
        userMigrationHashes[user].push(migrationHash);

        // Send cross-chain message
        _sendCrossChainMigrationMessage(migration, lockHash);

        emit CrossChainMigrationInitiated(
            user,
            token,
            amount,
            CURRENT_CHAIN_ID,
            targetChainId,
            migrationHash
        );

        return migrationHash;
    }

    function completeCrossChainMigration(
        bytes32 migrationHash,
        bytes calldata signature
    ) external override onlyAuthorizedRelayer nonReentrant returns (bool) {
        AssetMigration storage migration = migrations[migrationHash];
        require(!migration.completed, "Migration already completed");
        require(migration.migrationHash == migrationHash, "Invalid migration hash");
        require(
            block.timestamp <= migration.timestamp + MIGRATION_TIMEOUT,
            "Migration expired"
        );

        bytes32 completionHash = keccak256(
            abi.encodePacked(migration.user, migrationHash, block.timestamp)
        );

        ILitRelayContract.PKPSignature memory pkpSig = ILitRelayContract.PKPSignature({
            signature: signature,
            pkpAddress: _getUserPKPAddress(migration.user),
            timestamp: block.timestamp,
            messageHash: completionHash
        });

        require(
            litRelayContract.verifyPKPSignature(pkpSig, completionHash),
            "Invalid PKP signature"
        );

        // Complete migration
        migration.completed = true;

        // If this is the target chain, mint/unlock tokens for user
        if (migration.targetChainId == CURRENT_CHAIN_ID) {
            // In a real implementation, this would mint tokens or unlock from a pool
            // For now, we'll emit an event
            emit CrossChainMigrationCompleted(migration.user, migrationHash, true);
        }

        return true;
    }

    /**
     * @dev Get user's cross-chain portfolio
     * @param user User address
     * @return CrossChainPortfolio User's portfolio across chains
     */
    function getCrossChainPortfolio(
        address user
    ) external view override validUser(user) returns (CrossChainPortfolio memory) {
        return userPortfolios[user];
    }

    /**
     * @dev Check if asset is locked
     * @param user User address
     * @param token Token address
     * @param chainId Chain ID
     * @return bool True if locked
     */
    function isAssetLocked(
        address user,
        address token,
        uint256 chainId
    ) external view override returns (bool) {
        bytes32[] memory lockHashes = userLockHashes[user];
        
        for (uint256 i = 0; i < lockHashes.length; i++) {
            CrossChainAsset memory asset = lockedAssets[lockHashes[i]];
            if (asset.tokenAddress == token && asset.chainId == chainId && asset.isLocked) {
                return true;
            }
        }
        
        return false;
    }

    /**
     * @dev Get migration status
     * @param migrationHash Migration hash
     * @return AssetMigration Migration details
     */
    function getMigrationStatus(
        bytes32 migrationHash
    ) external view override returns (AssetMigration memory) {
        return migrations[migrationHash];
    }

    /**
     * @dev Get supported chains
     * @return uint256[] Array of supported chain IDs
     */
    function getSupportedChains() external view override returns (uint256[] memory) {
        return supportedChainsList;
    }

    /**
     * @dev Add supported chain
     * @param chainId Chain ID to add
     * @param contractAddress Contract address on the chain
     */
    function addSupportedChain(
        uint256 chainId,
        address contractAddress
    ) external onlyOwner {
        require(chainId > 0, "Invalid chain ID");
        require(contractAddress != address(0), "Invalid contract address");
        require(!supportedChains[chainId], "Chain already supported");
        require(supportedChainsList.length < MAX_SUPPORTED_CHAINS, "Too many chains");

        supportedChains[chainId] = true;
        chainActive[chainId] = true;
        chainContracts[chainId] = contractAddress;
        supportedChainsList.push(chainId);
    }

    /**
     * @dev Remove supported chain
     * @param chainId Chain ID to remove
     */
    function removeSupportedChain(uint256 chainId) external onlyOwner {
        require(chainId != CURRENT_CHAIN_ID, "Cannot remove current chain");
        require(supportedChains[chainId], "Chain not supported");

        supportedChains[chainId] = false;
        chainActive[chainId] = false;
        delete chainContracts[chainId];

        // Remove from array
        for (uint256 i = 0; i < supportedChainsList.length; i++) {
            if (supportedChainsList[i] == chainId) {
                supportedChainsList[i] = supportedChainsList[supportedChainsList.length - 1];
                supportedChainsList.pop();
                break;
            }
        }
    }

    /**
     * @dev Set chain active status
     * @param chainId Chain ID
     * @param active Active status
     */
    function setChainActive(uint256 chainId, bool active) external onlyOwner {
        require(supportedChains[chainId], "Chain not supported");
        chainActive[chainId] = active;
    }

    /**
     * @dev Set authorized relayer
     * @param relayer Relayer address
     * @param authorized Authorization status
     */
    function setAuthorizedRelayer(address relayer, bool authorized) external onlyOwner {
        require(relayer != address(0), "Invalid relayer address");
        authorizedRelayers[relayer] = authorized;
    }

    /**
     * @dev Set emergency coordinator
     * @param coordinator Coordinator address
     * @param authorized Authorization status
     */
    function setEmergencyCoordinator(address coordinator, bool authorized) external onlyOwner {
        require(coordinator != address(0), "Invalid coordinator address");
        emergencyCoordinators[coordinator] = authorized;
    }

    /**
     * @dev Emergency pause all cross-chain operations
     */
    function emergencyPauseAll() external onlyEmergencyCoordinator {
        for (uint256 i = 0; i < supportedChainsList.length; i++) {
            if (supportedChainsList[i] != CURRENT_CHAIN_ID) {
                chainActive[supportedChainsList[i]] = false;
            }
        }
    }

    /**
     * @dev Emergency resume all cross-chain operations
     */
    function emergencyResumeAll() external onlyOwner {
        for (uint256 i = 0; i < supportedChainsList.length; i++) {
            chainActive[supportedChainsList[i]] = true;
        }
    }

    /**
     * @dev Internal function to update cross-chain portfolio
     */
    function _updateCrossChainPortfolio(
        address user,
        address token,
        uint256 amount,
        uint256 chainId,
        bool isLock
    ) internal {
        CrossChainPortfolio storage portfolio = userPortfolios[user];
        
        if (portfolio.user == address(0)) {
            portfolio.user = user;
            portfolio.supportedChains = supportedChainsList;
        }

        // Find or create asset entry
        bool found = false;
        for (uint256 i = 0; i < portfolio.assets.length; i++) {
            if (portfolio.assets[i].tokenAddress == token && portfolio.assets[i].chainId == chainId) {
                if (isLock) {
                    portfolio.assets[i].amount += amount;
                } else {
                    portfolio.assets[i].amount = portfolio.assets[i].amount >= amount ? 
                        portfolio.assets[i].amount - amount : 0;
                }
                found = true;
                break;
            }
        }

        if (!found && isLock) {
            portfolio.assets.push(CrossChainAsset({
                tokenAddress: token,
                amount: amount,
                chainId: chainId,
                isLocked: true,
                lockTimestamp: block.timestamp,
                lockHash: bytes32(0)
            }));
        }

        portfolio.lastUpdated = block.timestamp;
    }

    /**
     * @dev Internal function to send cross-chain migration message
     */
    function _sendCrossChainMigrationMessage(
        AssetMigration memory migration,
        bytes32 lockHash
    ) internal {
        bytes memory payload = abi.encodeWithSignature(
            "completeCrossChainMigration(bytes32,bytes)",
            migration.migrationHash,
            ""
        );

        ILitRelayContract.CrossChainMessage memory message = ILitRelayContract.CrossChainMessage({
            sourceChainId: CURRENT_CHAIN_ID,
            targetChainId: migration.targetChainId,
            sourceContract: address(this),
            targetContract: chainContracts[migration.targetChainId],
            payload: payload,
            nonce: chainNonces[migration.targetChainId],
            timestamp: block.timestamp
        });

        litRelayContract.sendCrossChainMessage(message);
    }

    /**
     * @dev Internal function to get user's PKP address
     */
    function _getUserPKPAddress(address user) internal view returns (address) {
        if (address(litProtocolIntegration) != address(0)) {
            try litProtocolIntegration.getUserPKP(user) returns (ILitProtocolIntegration.PKPAuth memory pkpAuth) {
                return pkpAuth.pkpAddress;
            } catch {
                return address(0);
            }
        }
        return address(0);
    }

    /**
     * @dev Get user's lock hashes
     * @param user User address
     * @return bytes32[] Array of lock hashes
     */
    function getUserLockHashes(address user) external view returns (bytes32[] memory) {
        return userLockHashes[user];
    }

    /**
     * @dev Get user's migration hashes
     * @param user User address
     * @return bytes32[] Array of migration hashes
     */
    function getUserMigrationHashes(address user) external view returns (bytes32[] memory) {
        return userMigrationHashes[user];
    }

    /**
     * @dev Get locked asset details
     * @param lockHash Lock hash
     * @return CrossChainAsset Locked asset details
     */
    function getLockedAsset(bytes32 lockHash) external view returns (CrossChainAsset memory) {
        return lockedAssets[lockHash];
    }
}