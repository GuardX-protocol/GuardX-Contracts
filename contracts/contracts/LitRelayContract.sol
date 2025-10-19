// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/ILitRelayContract.sol";

/**
 * @title LitRelayContract
 * @dev Relay contract for Lit Protocol cross-chain operations and PKP signature verification
 * Handles cross-chain messaging, PKP authentication, and Lit Action execution triggers
 */
contract LitRelayContract is ILitRelayContract, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;


    // PKP registry
    mapping(address => bool) public registeredPKPs;
    mapping(address => bytes) public pkpPublicKeys;
    mapping(address => uint256) public pkpRegistrationTime;

    // Lit Action registry
    mapping(string => bool) public activeLitActions;
    mapping(string => uint256) public litActionLastExecution;
    mapping(string => address) public litActionOwners;

    // Cross-chain messaging
    mapping(bytes32 => bool) public processedMessages;
    mapping(uint256 => uint256) public chainNonces;
    mapping(uint256 => bool) public supportedChains;

    // Access control
    mapping(address => bool) public authorizedRelayers;
    mapping(address => bool) public emergencyExecutors;

    // Configuration
    uint256 public constant MESSAGE_VALIDITY_PERIOD = 1 hours;
    uint256 public constant MAX_CROSS_CHAIN_GAS = 500000;
    uint256 public immutable CHAIN_ID;

    // Events for monitoring
    event PKPRegistered(address indexed pkpAddress, uint256 timestamp);
    event LitActionRegistered(string indexed actionId, address indexed owner);
    event AuthorizedRelayerUpdated(address indexed relayer, bool authorized);
    event ChainSupportUpdated(uint256 indexed chainId, bool supported);

    modifier onlyAuthorizedRelayer() {
        require(
            authorizedRelayers[msg.sender] || msg.sender == owner(),
            "Not authorized relayer"
        );
        _;
    }

    modifier onlyEmergencyExecutor() {
        require(
            emergencyExecutors[msg.sender] || msg.sender == owner(),
            "Not emergency executor"
        );
        _;
    }

    modifier validChain(uint256 chainId) {
        require(supportedChains[chainId], "Chain not supported");
        _;
    }

    constructor() {
        CHAIN_ID = block.chainid;

        // Initialize supported chains (Ethereum, Polygon, Arbitrum)
        supportedChains[1] = true; // Ethereum Mainnet
        supportedChains[137] = true; // Polygon
        supportedChains[42161] = true; // Arbitrum One

        // Set deployer as authorized relayer
        authorizedRelayers[msg.sender] = true;
    }

    /**
     * @dev Verify PKP signature for a given message hash
     * @param signature PKP signature data
     * @param messageHash Hash of the message to verify
     * @return bool True if signature is valid
     */
    function verifyPKPSignature(
        PKPSignature calldata signature,
        bytes32 messageHash
    ) external override returns (bool) {
        require(registeredPKPs[signature.pkpAddress], "PKP not registered");
        require(
            signature.timestamp > block.timestamp - MESSAGE_VALIDITY_PERIOD,
            "Signature expired"
        );
        require(signature.messageHash == messageHash, "Message hash mismatch");

        // Verify ECDSA signature
        address recoveredSigner = messageHash.toEthSignedMessageHash().recover(
            signature.signature
        );

        bool isValid = recoveredSigner == signature.pkpAddress;
        emit PKPSignatureVerified(signature.pkpAddress, messageHash, isValid);

        return isValid;
    }

    /**
     * @dev Internal function to verify PKP signature without emitting events
     * @param signature PKP signature data
     * @param messageHash Hash of the message to verify
     * @return bool True if signature is valid
     */
    function _verifyPKPSignatureInternal(
        PKPSignature calldata signature,
        bytes32 messageHash
    ) internal view returns (bool) {
        if (!registeredPKPs[signature.pkpAddress]) return false;
        if (signature.timestamp <= block.timestamp - MESSAGE_VALIDITY_PERIOD)
            return false;
        if (signature.messageHash != messageHash) return false;

        // Verify ECDSA signature
        address recoveredSigner = messageHash.toEthSignedMessageHash().recover(
            signature.signature
        );

        return recoveredSigner == signature.pkpAddress;
    }

    function executeLitAction(
        LitActionExecution calldata execution
    ) external override onlyAuthorizedRelayer nonReentrant returns (bool) {
        require(activeLitActions[execution.actionId], "Lit Action not active");
        require(
            execution.timestamp > block.timestamp - MESSAGE_VALIDITY_PERIOD,
            "Execution expired"
        );

        // Verify PKP signature for the execution
        bytes32 executionHash = keccak256(
            abi.encodePacked(
                execution.actionId,
                execution.conditionHash,
                execution.executionData,
                execution.timestamp
            )
        );

        bool signatureValid = _verifyPKPSignatureInternal(
            execution.signature,
            executionHash
        );
        require(signatureValid, "Invalid PKP signature");

        // Update last execution time
        litActionLastExecution[execution.actionId] = block.timestamp;

        emit LitActionTriggered(
            execution.actionId,
            litActionOwners[execution.actionId],
            execution.conditionHash,
            block.timestamp
        );

        return true;
    }

    /**
     * @dev Send cross-chain message
     * @param message Cross-chain message data
     * @return bytes32 Message hash
     */
    function sendCrossChainMessage(
        CrossChainMessage calldata message
    )
        external
        override
        onlyAuthorizedRelayer
        validChain(message.targetChainId)
        returns (bytes32)
    {
        require(message.sourceChainId == CHAIN_ID, "Invalid source chain");
        require(
            message.timestamp > block.timestamp - MESSAGE_VALIDITY_PERIOD,
            "Message expired"
        );

        // Generate unique message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                message.sourceChainId,
                message.targetChainId,
                message.sourceContract,
                message.targetContract,
                message.payload,
                message.nonce,
                message.timestamp
            )
        );

        // Increment nonce for target chain
        chainNonces[message.targetChainId]++;

        emit CrossChainMessageSent(
            message.sourceChainId,
            message.targetChainId,
            messageHash,
            message.nonce
        );

        return messageHash;
    }

    /**
     * @dev Process incoming cross-chain message
     * @param message Cross-chain message data
     * @param signature PKP signature for the message
     * @return bool True if message was processed successfully
     */
    function processCrossChainMessage(
        CrossChainMessage calldata message,
        PKPSignature calldata signature
    ) external override onlyAuthorizedRelayer nonReentrant returns (bool) {
        require(message.targetChainId == CHAIN_ID, "Invalid target chain");
        require(
            supportedChains[message.sourceChainId],
            "Source chain not supported"
        );

        // Generate message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                message.sourceChainId,
                message.targetChainId,
                message.sourceContract,
                message.targetContract,
                message.payload,
                message.nonce,
                message.timestamp
            )
        );

        require(!processedMessages[messageHash], "Message already processed");
        require(
            message.timestamp > block.timestamp - MESSAGE_VALIDITY_PERIOD,
            "Message expired"
        );

        // Verify PKP signature
        bool signatureValid = _verifyPKPSignatureInternal(
            signature,
            messageHash
        );
        require(signatureValid, "Invalid PKP signature");

        // Mark message as processed
        processedMessages[messageHash] = true;

        // Execute the cross-chain call
        bool success = _executeCrossChainCall(message);

        emit CrossChainMessageReceived(
            message.sourceChainId,
            messageHash,
            success
        );

        return success;
    }

    /**
     * @dev Register a new PKP
     * @param pkpAddress PKP Ethereum address
     * @param publicKey PKP public key
     */
    function registerPKP(
        address pkpAddress,
        bytes calldata publicKey
    ) external override onlyAuthorizedRelayer {
        require(pkpAddress != address(0), "Invalid PKP address");
        require(publicKey.length > 0, "Invalid public key");
        require(!registeredPKPs[pkpAddress], "PKP already registered");

        registeredPKPs[pkpAddress] = true;
        pkpPublicKeys[pkpAddress] = publicKey;
        pkpRegistrationTime[pkpAddress] = block.timestamp;

        emit PKPRegistered(pkpAddress, block.timestamp);
    }

    /**
     * @dev Check if PKP is registered
     * @param pkpAddress PKP address to check
     * @return bool True if PKP is registered
     */
    function isPKPRegistered(
        address pkpAddress
    ) external view override returns (bool) {
        return registeredPKPs[pkpAddress];
    }

    /**
     * @dev Get Lit Action status
     * @param actionId Lit Action ID
     * @return active True if action is active
     * @return lastExecution Timestamp of last execution
     */
    function getLitActionStatus(
        string calldata actionId
    ) external view override returns (bool active, uint256 lastExecution) {
        active = activeLitActions[actionId];
        lastExecution = litActionLastExecution[actionId];
    }

    /**
     * @dev Register a new Lit Action
     * @param actionId Unique action identifier
     * @param owner Owner of the Lit Action
     */
    function registerLitAction(
        string calldata actionId,
        address owner
    ) external onlyAuthorizedRelayer {
        require(bytes(actionId).length > 0, "Invalid action ID");
        require(owner != address(0), "Invalid owner");
        require(!activeLitActions[actionId], "Action already registered");

        activeLitActions[actionId] = true;
        litActionOwners[actionId] = owner;

        emit LitActionRegistered(actionId, owner);
    }

    /**
     * @dev Deactivate a Lit Action
     * @param actionId Action ID to deactivate
     */
    function deactivateLitAction(string calldata actionId) external {
        require(
            litActionOwners[actionId] == msg.sender || msg.sender == owner(),
            "Not authorized to deactivate"
        );
        require(activeLitActions[actionId], "Action not active");

        activeLitActions[actionId] = false;
    }

    /**
     * @dev Set authorized relayer status
     * @param relayer Address to update
     * @param authorized True to authorize, false to revoke
     */
    function setAuthorizedRelayer(
        address relayer,
        bool authorized
    ) external onlyOwner {
        require(relayer != address(0), "Invalid relayer address");
        authorizedRelayers[relayer] = authorized;
        emit AuthorizedRelayerUpdated(relayer, authorized);
    }

    /**
     * @dev Set emergency executor status
     * @param executor Address to update
     * @param authorized True to authorize, false to revoke
     */
    function setEmergencyExecutor(
        address executor,
        bool authorized
    ) external onlyOwner {
        require(executor != address(0), "Invalid executor address");
        emergencyExecutors[executor] = authorized;
    }

    /**
     * @dev Update supported chain status
     * @param chainId Chain ID to update
     * @param supported True to support, false to remove support
     */
    function setSupportedChain(
        uint256 chainId,
        bool supported
    ) external onlyOwner {
        require(chainId > 0, "Invalid chain ID");
        supportedChains[chainId] = supported;
        emit ChainSupportUpdated(chainId, supported);
    }

    /**
     * @dev Emergency function to process urgent cross-chain operations
     * @param message Cross-chain message
     * @param signature PKP signature
     */
    function emergencyProcessMessage(
        CrossChainMessage calldata message,
        PKPSignature calldata signature
    ) external onlyEmergencyExecutor nonReentrant returns (bool) {
        // Skip some validations for emergency processing
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                message.sourceChainId,
                message.targetChainId,
                message.sourceContract,
                message.targetContract,
                message.payload,
                message.nonce,
                message.timestamp
            )
        );

        require(!processedMessages[messageHash], "Message already processed");

        // Verify PKP signature
        bool signatureValid = _verifyPKPSignatureInternal(
            signature,
            messageHash
        );
        require(signatureValid, "Invalid PKP signature");

        processedMessages[messageHash] = true;
        return _executeCrossChainCall(message);
    }

    /**
     * @dev Internal function to execute cross-chain calls
     * @param message Cross-chain message data
     * @return bool True if call was successful
     */
    function _executeCrossChainCall(
        CrossChainMessage memory message
    ) internal returns (bool) {
        // Execute the call to the target contract
        (bool success, ) = message.targetContract.call{
            gas: MAX_CROSS_CHAIN_GAS
        }(message.payload);

        return success;
    }

    /**
     * @dev Get chain nonce for a specific chain
     * @param chainId Chain ID
     * @return uint256 Current nonce
     */
    function getChainNonce(uint256 chainId) external view returns (uint256) {
        return chainNonces[chainId];
    }

    /**
     * @dev Check if message has been processed
     * @param messageHash Message hash to check
     * @return bool True if processed
     */
    function isMessageProcessed(
        bytes32 messageHash
    ) external view returns (bool) {
        return processedMessages[messageHash];
    }

    /**
     * @dev Get PKP public key
     * @param pkpAddress PKP address
     * @return bytes Public key data
     */
    function getPKPPublicKey(
        address pkpAddress
    ) external view returns (bytes memory) {
        require(registeredPKPs[pkpAddress], "PKP not registered");
        return pkpPublicKeys[pkpAddress];
    }
}
