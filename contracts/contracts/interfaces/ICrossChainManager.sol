// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICrossChainManager
 * @dev Interface for cross-chain asset management and coordination
 */
interface ICrossChainManager {
    struct CrossChainAsset {
        address tokenAddress;
        uint256 amount;
        uint256 chainId;
        bool isLocked;
        uint256 lockTimestamp;
        bytes32 lockHash;
    }

    struct CrossChainPortfolio {
        address user;
        CrossChainAsset[] assets;
        uint256 totalValueUSD;
        uint256 lastUpdated;
        uint256[] supportedChains;
    }

    struct AssetMigration {
        address user;
        address tokenAddress;
        uint256 amount;
        uint256 sourceChainId;
        uint256 targetChainId;
        bytes32 migrationHash;
        uint256 timestamp;
        bool completed;
    }

    struct CrossChainMessage {
        uint256 sourceChainId;
        uint256 targetChainId;
        address sourceContract;
        address targetContract;
        bytes payload;
        uint256 nonce;
        uint256 timestamp;
        bytes32 messageHash;
    }

    event AssetLocked(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 indexed chainId,
        bytes32 lockHash
    );

    event AssetUnlocked(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 indexed chainId,
        bytes32 lockHash
    );

    event CrossChainMigrationInitiated(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 sourceChainId,
        uint256 targetChainId,
        bytes32 migrationHash
    );

    event CrossChainMigrationCompleted(
        address indexed user,
        bytes32 indexed migrationHash,
        bool success
    );

    event CrossChainEmergencyTriggered(
        address indexed user,
        uint256[] chainIds,
        uint256 timestamp
    );

    function lockAsset(
        address user,
        address token,
        uint256 amount,
        uint256 targetChainId
    ) external returns (bytes32);

    function unlockAsset(
        address user,
        bytes32 lockHash,
        bytes calldata signature
    ) external returns (bool);

    function initiateCrossChainMigration(
        address user,
        address token,
        uint256 amount,
        uint256 targetChainId
    ) external returns (bytes32);

    function completeCrossChainMigration(
        bytes32 migrationHash,
        bytes calldata signature
    ) external returns (bool);

    function getCrossChainPortfolio(
        address user
    ) external view returns (CrossChainPortfolio memory);

    function isAssetLocked(
        address user,
        address token,
        uint256 chainId
    ) external view returns (bool);

    function getMigrationStatus(
        bytes32 migrationHash
    ) external view returns (AssetMigration memory);

    function getSupportedChains() external view returns (uint256[] memory);
}