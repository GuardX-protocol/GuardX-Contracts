// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILitRelayContract
 * @dev Interface for Lit Protocol relay contract for cross-chain operations
 */
interface ILitRelayContract {
    struct PKPSignature {
        bytes signature;
        address pkpAddress;
        uint256 timestamp;
        bytes32 messageHash;
    }

    struct CrossChainMessage {
        uint256 sourceChainId;
        uint256 targetChainId;
        address sourceContract;
        address targetContract;
        bytes payload;
        uint256 nonce;
        uint256 timestamp;
    }

    struct LitActionExecution {
        string actionId;
        bytes32 conditionHash;
        bytes executionData;
        PKPSignature signature;
        uint256 timestamp;
    }

    event PKPSignatureVerified(
        address indexed pkpAddress,
        bytes32 indexed messageHash,
        bool verified
    );

    event LitActionTriggered(
        string indexed actionId,
        address indexed user,
        bytes32 conditionHash,
        uint256 timestamp
    );

    event CrossChainMessageSent(
        uint256 indexed sourceChainId,
        uint256 indexed targetChainId,
        bytes32 indexed messageHash,
        uint256 nonce
    );

    event CrossChainMessageReceived(
        uint256 indexed sourceChainId,
        bytes32 indexed messageHash,
        bool processed
    );

    function verifyPKPSignature(
        PKPSignature calldata signature,
        bytes32 messageHash
    ) external returns (bool);

    function executeLitAction(
        LitActionExecution calldata execution
    ) external returns (bool);

    function sendCrossChainMessage(
        CrossChainMessage calldata message
    ) external returns (bytes32);

    function processCrossChainMessage(
        CrossChainMessage calldata message,
        PKPSignature calldata signature
    ) external returns (bool);

    function registerPKP(address pkpAddress, bytes calldata publicKey) external;

    function isPKPRegistered(address pkpAddress) external view returns (bool);

    function getLitActionStatus(string calldata actionId) external view returns (bool active, uint256 lastExecution);
}