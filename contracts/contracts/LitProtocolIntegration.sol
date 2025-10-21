// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/ILitProtocolIntegration.sol";
import "./interfaces/ILitRelayContract.sol";


contract LitProtocolIntegration is ILitProtocolIntegration, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;


    // Lit Relay Contract reference
    ILitRelayContract public litRelayContract;

    // User PKP mappings
    mapping(address => PKPAuth) public userPKPs;
    mapping(address => bool) public hasPKP;

    // Conditional access mappings
    mapping(address => mapping(bytes32 => ConditionalAccess)) public userConditionalAccess;
    mapping(address => bytes32[]) public userAccessConditions;

    // Encrypted data mappings
    mapping(address => mapping(bytes32 => EncryptedData)) public userEncryptedData;
    mapping(address => bytes32[]) public userDataHashes;

    // Lit Action authorization
    mapping(string => mapping(address => bool)) public litActionAuthorizations;
    mapping(string => bool) public registeredLitActions;

    // Access control
    mapping(address => bool) public authorizedIntegrators;

    // Configuration
    uint256 public constant MAX_ACCESS_CONDITIONS = 10;
    uint256 public constant MAX_ENCRYPTED_DATA_ENTRIES = 50;
    uint256 public constant ACCESS_CONDITION_VALIDITY = 30 days;

    modifier onlyAuthorizedIntegrator() {
        require(
            authorizedIntegrators[msg.sender] || msg.sender == owner(),
            "Not authorized integrator"
        );
        _;
    }

    modifier validUser(address user) {
        require(user != address(0), "Invalid user address");
        _;
    }

    modifier hasPKPAuth(address user) {
        require(hasPKP[user], "User has no PKP authentication");
        require(userPKPs[user].isActive, "PKP authentication inactive");
        _;
    }

    constructor(address _litRelayContract) {
        require(_litRelayContract != address(0), "Invalid Lit Relay Contract");
        litRelayContract = ILitRelayContract(_litRelayContract);
        authorizedIntegrators[msg.sender] = true;
    }

    /**
     * @dev Authenticate user with PKP
     * @param user User address
     * @param pkpAuth PKP authentication data
     * @param signature PKP signature for authentication
     * @return bool True if authentication successful
     */
    function authenticateWithPKP(
        address user,
        PKPAuth calldata pkpAuth,
        bytes calldata signature
    ) external override onlyAuthorizedIntegrator validUser(user) returns (bool) {
        require(pkpAuth.pkpAddress != address(0), "Invalid PKP address");
        require(pkpAuth.publicKey.length > 0, "Invalid public key");
        require(pkpAuth.threshold > 0, "Invalid threshold");

        // Verify PKP is registered with Lit Relay Contract
        require(
            litRelayContract.isPKPRegistered(pkpAuth.pkpAddress),
            "PKP not registered with relay"
        );

        // Create authentication message hash
        bytes32 authHash = keccak256(
            abi.encodePacked(
                user,
                pkpAuth.pkpAddress,
                pkpAuth.publicKey,
                pkpAuth.threshold,
                block.timestamp
            )
        );

        // Verify signature
        address recoveredSigner = authHash.toEthSignedMessageHash().recover(signature);
        require(recoveredSigner == pkpAuth.pkpAddress, "Invalid PKP signature");

        // Store PKP authentication
        userPKPs[user] = PKPAuth({
            pkpAddress: pkpAuth.pkpAddress,
            publicKey: pkpAuth.publicKey,
            threshold: pkpAuth.threshold,
            isActive: true
        });

        hasPKP[user] = true;

        emit PKPAuthenticated(user, pkpAuth.pkpAddress, block.timestamp);
        return true;
    }

    /**
     * @dev Create conditional access for user
     * @param user User address
     * @param access Conditional access data
     * @return bytes32 Condition hash
     */
    function createConditionalAccess(
        address user,
        ConditionalAccess calldata access
    ) external override onlyAuthorizedIntegrator validUser(user) hasPKPAuth(user) returns (bytes32) {
        require(bytes(access.accessConditions).length > 0, "Empty access conditions");
        require(access.expiresAt > block.timestamp, "Access condition already expired");
        require(
            userAccessConditions[user].length < MAX_ACCESS_CONDITIONS,
            "Too many access conditions"
        );

        // Generate condition hash
        bytes32 conditionHash = keccak256(
            abi.encodePacked(
                user,
                access.accessConditions,
                access.createdAt,
                access.expiresAt,
                block.timestamp
            )
        );

        // Store conditional access
        userConditionalAccess[user][conditionHash] = ConditionalAccess({
            conditionHash: conditionHash,
            accessConditions: access.accessConditions,
            isActive: true,
            createdAt: block.timestamp,
            expiresAt: access.expiresAt
        });

        userAccessConditions[user].push(conditionHash);

        emit ConditionalAccessCreated(user, conditionHash, block.timestamp);
        return conditionHash;
    }

    /**
     * @dev Store encrypted data for user
     * @param user User address
     * @param data Encrypted data
     * @return bytes32 Data hash
     */
    function storeEncryptedData(
        address user,
        EncryptedData calldata data
    ) external override onlyAuthorizedIntegrator validUser(user) hasPKPAuth(user) returns (bytes32) {
        require(data.encryptedContent.length > 0, "Empty encrypted content");
        require(bytes(data.ipfsHash).length > 0, "Empty IPFS hash");
        require(
            userDataHashes[user].length < MAX_ENCRYPTED_DATA_ENTRIES,
            "Too many encrypted data entries"
        );

        // Generate data hash
        bytes32 dataHash = keccak256(
            abi.encodePacked(
                user,
                data.encryptedContent,
                data.accessControlHash,
                data.ipfsHash,
                block.timestamp
            )
        );

        // Store encrypted data
        userEncryptedData[user][dataHash] = EncryptedData({
            encryptedContent: data.encryptedContent,
            accessControlHash: data.accessControlHash,
            ipfsHash: data.ipfsHash,
            timestamp: block.timestamp
        });

        userDataHashes[user].push(dataHash);

        emit EncryptedDataStored(user, dataHash, data.ipfsHash, block.timestamp);
        return dataHash;
    }

    /**
     * @dev Verify conditional access for user
     * @param user User address
     * @param conditionHash Condition hash to verify
     * @return bool True if access is valid
     */
    function verifyConditionalAccess(
        address user,
        bytes32 conditionHash
    ) external view override validUser(user) returns (bool) {
        if (!hasPKP[user]) return false;

        ConditionalAccess memory access = userConditionalAccess[user][conditionHash];
        
        return access.isActive && 
               access.expiresAt > block.timestamp && 
               access.conditionHash == conditionHash;
    }

    /**
     * @dev Get user's PKP authentication data
     * @param user User address
     * @return PKPAuth User's PKP data
     */
    function getUserPKP(address user) external view override validUser(user) returns (PKPAuth memory) {
        require(hasPKP[user], "User has no PKP");
        return userPKPs[user];
    }

    /**
     * @dev Check if user is authorized by Lit Action
     * @param user User address
     * @param actionId Lit Action ID
     * @param executionData Execution data to verify
     * @return bool True if authorized
     */
    function isAuthorizedByLitAction(
        address user,
        string calldata actionId,
        bytes calldata executionData
    ) external view override validUser(user) returns (bool) {
        if (!registeredLitActions[actionId]) return false;
        if (!litActionAuthorizations[actionId][user]) return false;

        // Check if Lit Action is active in relay contract
        (bool active, ) = litRelayContract.getLitActionStatus(actionId);
        return active;
    }

    /**
     * @dev Register Lit Action for user authorization
     * @param actionId Lit Action ID
     * @param user User to authorize
     */
    function registerLitActionAuthorization(
        string calldata actionId,
        address user
    ) external onlyAuthorizedIntegrator validUser(user) {
        require(bytes(actionId).length > 0, "Invalid action ID");
        
        // Verify Lit Action exists in relay contract
        (bool active, ) = litRelayContract.getLitActionStatus(actionId);
        require(active, "Lit Action not active in relay");

        registeredLitActions[actionId] = true;
        litActionAuthorizations[actionId][user] = true;

        emit LitActionExecuted(user, actionId, true, block.timestamp);
    }

    /**
     * @dev Revoke Lit Action authorization for user
     * @param actionId Lit Action ID
     * @param user User to revoke authorization
     */
    function revokeLitActionAuthorization(
        string calldata actionId,
        address user
    ) external {
        require(
            msg.sender == user || msg.sender == owner() || authorizedIntegrators[msg.sender],
            "Not authorized to revoke"
        );
        
        litActionAuthorizations[actionId][user] = false;
    }

    /**
     * @dev Deactivate user's PKP authentication
     * @param user User address
     */
    function deactivatePKP(address user) external {
        require(
            msg.sender == user || msg.sender == owner() || authorizedIntegrators[msg.sender],
            "Not authorized to deactivate"
        );
        require(hasPKP[user], "User has no PKP");

        userPKPs[user].isActive = false;
    }

    /**
     * @dev Reactivate user's PKP authentication
     * @param user User address
     */
    function reactivatePKP(address user) external onlyAuthorizedIntegrator validUser(user) {
        require(hasPKP[user], "User has no PKP");
        userPKPs[user].isActive = true;
    }

    /**
     * @dev Remove expired conditional access entries
     * @param user User address
     * @param conditionHash Condition hash to remove
     */
    function removeExpiredConditionalAccess(
        address user,
        bytes32 conditionHash
    ) external validUser(user) {
        ConditionalAccess storage access = userConditionalAccess[user][conditionHash];
        require(access.conditionHash != bytes32(0), "Condition not found");
        require(access.expiresAt <= block.timestamp, "Condition not expired");

        access.isActive = false;
    }

    /**
     * @dev Set authorized integrator status
     * @param integrator Address to update
     * @param authorized True to authorize, false to revoke
     */
    function setAuthorizedIntegrator(address integrator, bool authorized) external onlyOwner {
        require(integrator != address(0), "Invalid integrator address");
        authorizedIntegrators[integrator] = authorized;
    }

    /**
     * @dev Update Lit Relay Contract address
     * @param _litRelayContract New relay contract address
     */
    function setLitRelayContract(address _litRelayContract) external onlyOwner {
        require(_litRelayContract != address(0), "Invalid relay contract");
        litRelayContract = ILitRelayContract(_litRelayContract);
    }

    /**
     * @dev Get user's conditional access conditions
     * @param user User address
     * @return bytes32[] Array of condition hashes
     */
    function getUserAccessConditions(address user) external view validUser(user) returns (bytes32[] memory) {
        return userAccessConditions[user];
    }

    /**
     * @dev Get user's encrypted data hashes
     * @param user User address
     * @return bytes32[] Array of data hashes
     */
    function getUserDataHashes(address user) external view validUser(user) returns (bytes32[] memory) {
        return userDataHashes[user];
    }

    /**
     * @dev Get encrypted data by hash
     * @param user User address
     * @param dataHash Data hash
     * @return EncryptedData Encrypted data entry
     */
    function getEncryptedData(
        address user,
        bytes32 dataHash
    ) external view validUser(user) returns (EncryptedData memory) {
        return userEncryptedData[user][dataHash];
    }

    /**
     * @dev Get conditional access by hash
     * @param user User address
     * @param conditionHash Condition hash
     * @return ConditionalAccess Conditional access entry
     */
    function getConditionalAccess(
        address user,
        bytes32 conditionHash
    ) external view validUser(user) returns (ConditionalAccess memory) {
        return userConditionalAccess[user][conditionHash];
    }

    /**
     * @dev Check if Lit Action is registered
     * @param actionId Lit Action ID
     * @return bool True if registered
     */
    function isLitActionRegistered(string calldata actionId) external view returns (bool) {
        return registeredLitActions[actionId];
    }

    /**
     * @dev Emergency function to disable all PKP authentications
     */
    function emergencyDisableAllPKPs() external onlyOwner {
        // This would require additional tracking in a real implementation
        // For now, this is a placeholder for emergency controls
    }
}