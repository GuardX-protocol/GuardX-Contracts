// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILitProtocolIntegration
 * @dev Interface for Lit Protocol integration with existing contracts
 */
interface ILitProtocolIntegration {
    struct PKPAuth {
        address pkpAddress;
        bytes publicKey;
        uint256 threshold;
        bool isActive;
    }

    struct ConditionalAccess {
        bytes32 conditionHash;
        string accessConditions;
        bool isActive;
        uint256 createdAt;
        uint256 expiresAt;
    }

    struct EncryptedData {
        bytes encryptedContent;
        bytes32 accessControlHash;
        string ipfsHash;
        uint256 timestamp;
    }

    event PKPAuthenticated(
        address indexed user,
        address indexed pkpAddress,
        uint256 timestamp
    );

    event ConditionalAccessCreated(
        address indexed user,
        bytes32 indexed conditionHash,
        uint256 timestamp
    );

    event EncryptedDataStored(
        address indexed user,
        bytes32 indexed dataHash,
        string ipfsHash,
        uint256 timestamp
    );

    event LitActionExecuted(
        address indexed user,
        string indexed actionId,
        bool success,
        uint256 timestamp
    );

    function authenticateWithPKP(
        address user,
        PKPAuth calldata pkpAuth,
        bytes calldata signature
    ) external returns (bool);

    function createConditionalAccess(
        address user,
        ConditionalAccess calldata access
    ) external returns (bytes32);

    function storeEncryptedData(
        address user,
        EncryptedData calldata data
    ) external returns (bytes32);

    function verifyConditionalAccess(
        address user,
        bytes32 conditionHash
    ) external view returns (bool);

    function getUserPKP(address user) external view returns (PKPAuth memory);

    function isAuthorizedByLitAction(
        address user,
        string calldata actionId,
        bytes calldata executionData
    ) external view returns (bool);
}