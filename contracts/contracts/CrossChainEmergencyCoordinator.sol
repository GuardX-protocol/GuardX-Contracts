// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/ICrossChainEmergencyCoordinator.sol";
import "./interfaces/ILitRelayContract.sol";
import "./interfaces/ILitProtocolIntegration.sol";
import "./interfaces/ICrossChainManager.sol";

/**
 * @title CrossChainEmergencyCoordinator
 * @dev Coordinates emergency protection actions across multiple blockchain networks
 */
contract CrossChainEmergencyCoordinator is ICrossChainEmergencyCoordinator, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;


    // Core contracts
    ILitRelayContract public litRelayContract;
    ILitProtocolIntegration public litProtocolIntegration;
    ICrossChainManager public crossChainManager;

    // Emergency coordination state
    mapping(bytes32 => EmergencyCoordination) public emergencyCoordinations;
    mapping(address => bytes32[]) public userEmergencyHashes;
    mapping(uint256 => ChainEmergencyStatus) public chainEmergencyStatus;

    // Governance state
    mapping(bytes32 => CrossChainGovernance) public governanceProposals;
    mapping(bytes32 => mapping(address => bool)) public hasVoted;
    mapping(address => bool) public governanceMembers;
    uint256 public governanceThreshold = 3; // Minimum votes needed

    // Access control
    mapping(address => bool) public emergencyExecutors;
    mapping(address => bool) public coordinators;

    // Configuration
    uint256 public constant COORDINATION_TIMEOUT = 30 minutes;
    uint256 public constant GOVERNANCE_VOTING_PERIOD = 7 days;
    uint256 public constant MAX_CHAINS_PER_EMERGENCY = 5;

    // Emergency state
    mapping(uint256 => bool) public chainsPaused;
    bool public globalEmergencyActive = false;

    modifier onlyEmergencyExecutor() {
        require(
            emergencyExecutors[msg.sender] || msg.sender == owner(),
            "Not emergency executor"
        );
        _;
    }

    modifier onlyCoordinator() {
        require(
            coordinators[msg.sender] || msg.sender == owner(),
            "Not coordinator"
        );
        _;
    }

    modifier onlyGovernanceMember() {
        require(governanceMembers[msg.sender], "Not governance member");
        _;
    }

    modifier notGlobalEmergency() {
        require(!globalEmergencyActive, "Global emergency active");
        _;
    }

    constructor(
        address _litRelayContract,
        address _litProtocolIntegration,
        address _crossChainManager
    ) {
        require(_litRelayContract != address(0), "Invalid Lit Relay Contract");
        require(_litProtocolIntegration != address(0), "Invalid Lit Protocol Integration");
        require(_crossChainManager != address(0), "Invalid Cross Chain Manager");

        litRelayContract = ILitRelayContract(_litRelayContract);
        litProtocolIntegration = ILitProtocolIntegration(_litProtocolIntegration);
        crossChainManager = ICrossChainManager(_crossChainManager);

        // Set deployer as initial governance member and coordinator
        governanceMembers[msg.sender] = true;
        coordinators[msg.sender] = true;
        emergencyExecutors[msg.sender] = true;
    }

    /**
     * @dev Initiate multi-chain emergency protection
     * @param user User address to protect
     * @param chainIds Array of chain IDs to coordinate
     * @param litActionIds Array of Lit Action IDs for each chain
     * @return bytes32 Coordination hash
     */
    function initiateMultiChainEmergency(
        address user,
        uint256[] calldata chainIds,
        string[] calldata litActionIds
    ) external override onlyEmergencyExecutor notGlobalEmergency returns (bytes32) {
        require(user != address(0), "Invalid user address");
        require(chainIds.length > 0, "No chains specified");
        require(chainIds.length == litActionIds.length, "Array length mismatch");
        require(chainIds.length <= MAX_CHAINS_PER_EMERGENCY, "Too many chains");

        // Verify all chains are supported
        uint256[] memory supportedChains = crossChainManager.getSupportedChains();
        for (uint256 i = 0; i < chainIds.length; i++) {
            bool chainSupported = false;
            for (uint256 j = 0; j < supportedChains.length; j++) {
                if (supportedChains[j] == chainIds[i]) {
                    chainSupported = true;
                    break;
                }
            }
            require(chainSupported, "Chain not supported");
            require(!chainsPaused[chainIds[i]], "Chain paused");
        }

        // Generate coordination hash
        bytes32 coordinationHash = keccak256(
            abi.encode(
                user,
                chainIds,
                litActionIds,
                block.timestamp,
                block.number
            )
        );

        // Create emergency coordination
        EmergencyCoordination memory coordination = EmergencyCoordination({
            user: user,
            chainIds: chainIds,
            litActionIds: litActionIds,
            coordinationHash: coordinationHash,
            timestamp: block.timestamp,
            executed: false,
            executedChains: 0
        });

        emergencyCoordinations[coordinationHash] = coordination;
        userEmergencyHashes[user].push(coordinationHash);

        // Send cross-chain messages to initiate emergency on each chain
        _sendEmergencyMessages(coordination);

        emit CrossChainEmergencyInitiated(user, coordinationHash, chainIds, block.timestamp);
        return coordinationHash;
    }

    /**
     * @dev Execute emergency protection on specific chain
     * @param coordinationHash Emergency coordination hash
     * @param chainId Chain ID to execute on
     * @param signature PKP signature authorizing execution
     * @return bool True if successful
     */
    function executeChainEmergency(
        bytes32 coordinationHash,
        uint256 chainId,
        bytes calldata signature
    ) external override onlyEmergencyExecutor nonReentrant returns (bool) {
        EmergencyCoordination storage coordination = emergencyCoordinations[coordinationHash];
        require(coordination.coordinationHash == coordinationHash, "Invalid coordination hash");
        require(!coordination.executed, "Emergency already executed");
        require(
            block.timestamp <= coordination.timestamp + COORDINATION_TIMEOUT,
            "Coordination expired"
        );

        // Verify chain is in the coordination
        bool chainFound = false;
        string memory litActionId = "";
        for (uint256 i = 0; i < coordination.chainIds.length; i++) {
            if (coordination.chainIds[i] == chainId) {
                chainFound = true;
                litActionId = coordination.litActionIds[i];
                break;
            }
        }
        require(chainFound, "Chain not in coordination");

        // Verify PKP signature
        bytes32 executionHash = keccak256(
            abi.encodePacked(
                coordination.user,
                coordinationHash,
                chainId,
                litActionId,
                block.timestamp
            )
        );

        address pkpAddress = _getUserPKPAddress(coordination.user);
        require(pkpAddress != address(0), "No PKP found for user");

        ILitRelayContract.PKPSignature memory pkpSig = ILitRelayContract.PKPSignature({
            signature: signature,
            pkpAddress: pkpAddress,
            timestamp: block.timestamp,
            messageHash: executionHash
        });

        bool signatureValid = litRelayContract.verifyPKPSignature(pkpSig, executionHash);
        require(signatureValid, "Invalid PKP signature");

        // Update chain emergency status
        ChainEmergencyStatus storage chainStatus = chainEmergencyStatus[chainId];
        chainStatus.chainId = chainId;
        chainStatus.emergencyActive = true;
        chainStatus.lastExecution = block.timestamp;
        chainStatus.executionCount++;
        chainStatus.lastExecutionHash = executionHash;

        // Update coordination
        coordination.executedChains++;

        // Check if all chains have been executed
        if (coordination.executedChains >= coordination.chainIds.length) {
            coordination.executed = true;
            emit CrossChainEmergencyCompleted(
                coordination.user,
                coordinationHash,
                coordination.executedChains,
                coordination.chainIds.length
            );
        }

        emit CrossChainEmergencyExecuted(coordination.user, coordinationHash, chainId, true);
        return true;
    }

    /**
     * @dev Get emergency coordination details
     * @param coordinationHash Coordination hash
     * @return EmergencyCoordination Coordination details
     */
    function getEmergencyCoordination(
        bytes32 coordinationHash
    ) external view override returns (EmergencyCoordination memory) {
        return emergencyCoordinations[coordinationHash];
    }

    /**
     * @dev Get chain emergency status
     * @param chainId Chain ID
     * @return ChainEmergencyStatus Chain status
     */
    function getChainEmergencyStatus(
        uint256 chainId
    ) external view override returns (ChainEmergencyStatus memory) {
        return chainEmergencyStatus[chainId];
    }

    /**
     * @dev Check if emergency is active on chain
     * @param chainId Chain ID
     * @return bool True if emergency active
     */
    function isEmergencyActive(uint256 chainId) external view override returns (bool) {
        return chainEmergencyStatus[chainId].emergencyActive;
    }

    /**
     * @dev Propose governance action
     * @param description Proposal description
     * @param targetChains Target chains for execution
     * @param executionData Execution data for each chain
     * @return bytes32 Proposal hash
     */
    function proposeGovernanceAction(
        string calldata description,
        uint256[] calldata targetChains,
        bytes[] calldata executionData
    ) external override onlyGovernanceMember returns (bytes32) {
        require(bytes(description).length > 0, "Empty description");
        require(targetChains.length > 0, "No target chains");
        require(targetChains.length == executionData.length, "Array length mismatch");

        bytes32 proposalHash = keccak256(
            abi.encode(
                description,
                targetChains,
                executionData,
                block.timestamp,
                msg.sender
            )
        );

        CrossChainGovernance memory proposal = CrossChainGovernance({
            proposalHash: proposalHash,
            description: description,
            targetChains: targetChains,
            executionData: executionData,
            votesFor: 0,
            votesAgainst: 0,
            deadline: block.timestamp + GOVERNANCE_VOTING_PERIOD,
            executed: false
        });

        governanceProposals[proposalHash] = proposal;

        emit CrossChainGovernanceProposal(proposalHash, targetChains, proposal.deadline);
        return proposalHash;
    }

    /**
     * @dev Vote on governance proposal
     * @param proposalHash Proposal hash
     * @param support True for support, false for against
     */
    function voteOnGovernanceProposal(
        bytes32 proposalHash,
        bool support
    ) external override onlyGovernanceMember {
        CrossChainGovernance storage proposal = governanceProposals[proposalHash];
        require(proposal.proposalHash == proposalHash, "Proposal not found");
        require(block.timestamp <= proposal.deadline, "Voting period ended");
        require(!hasVoted[proposalHash][msg.sender], "Already voted");

        hasVoted[proposalHash][msg.sender] = true;

        if (support) {
            proposal.votesFor++;
        } else {
            proposal.votesAgainst++;
        }
    }

    /**
     * @dev Execute governance proposal
     * @param proposalHash Proposal hash
     * @return bool True if successful
     */
    function executeGovernanceProposal(
        bytes32 proposalHash
    ) external override onlyGovernanceMember returns (bool) {
        CrossChainGovernance storage proposal = governanceProposals[proposalHash];
        require(proposal.proposalHash == proposalHash, "Proposal not found");
        require(block.timestamp > proposal.deadline, "Voting period not ended");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.votesFor >= governanceThreshold, "Insufficient votes");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal rejected");

        proposal.executed = true;

        // Execute on each target chain
        for (uint256 i = 0; i < proposal.targetChains.length; i++) {
            _executeGovernanceOnChain(proposal.targetChains[i], proposal.executionData[i]);
        }

        emit CrossChainGovernanceExecuted(proposalHash, proposal.targetChains, true);
        return true;
    }

    /**
     * @dev Emergency pause specific chain
     * @param chainId Chain ID to pause
     */
    function emergencyPauseChain(uint256 chainId) external override onlyEmergencyExecutor {
        chainsPaused[chainId] = true;
        chainEmergencyStatus[chainId].emergencyActive = true;
    }

    /**
     * @dev Emergency resume specific chain
     * @param chainId Chain ID to resume
     */
    function emergencyResumeChain(uint256 chainId) external override onlyCoordinator {
        chainsPaused[chainId] = false;
        chainEmergencyStatus[chainId].emergencyActive = false;
    }

    /**
     * @dev Set global emergency status
     * @param active Emergency status
     */
    function setGlobalEmergency(bool active) external onlyOwner {
        globalEmergencyActive = active;
    }

    /**
     * @dev Set governance threshold
     * @param threshold New threshold
     */
    function setGovernanceThreshold(uint256 threshold) external onlyOwner {
        require(threshold > 0, "Invalid threshold");
        governanceThreshold = threshold;
    }

    /**
     * @dev Add governance member
     * @param member Member address
     */
    function addGovernanceMember(address member) external onlyOwner {
        require(member != address(0), "Invalid member address");
        governanceMembers[member] = true;
    }

    /**
     * @dev Remove governance member
     * @param member Member address
     */
    function removeGovernanceMember(address member) external onlyOwner {
        governanceMembers[member] = false;
    }

    /**
     * @dev Set emergency executor status
     * @param executor Executor address
     * @param authorized Authorization status
     */
    function setEmergencyExecutor(address executor, bool authorized) external onlyOwner {
        require(executor != address(0), "Invalid executor address");
        emergencyExecutors[executor] = authorized;
    }

    /**
     * @dev Set coordinator status
     * @param coordinator Coordinator address
     * @param authorized Authorization status
     */
    function setCoordinator(address coordinator, bool authorized) external onlyOwner {
        require(coordinator != address(0), "Invalid coordinator address");
        coordinators[coordinator] = authorized;
    }

    /**
     * @dev Internal function to send emergency messages to all chains
     */
    function _sendEmergencyMessages(EmergencyCoordination memory coordination) internal {
        for (uint256 i = 0; i < coordination.chainIds.length; i++) {
            uint256 chainId = coordination.chainIds[i];
            string memory litActionId = coordination.litActionIds[i];

            bytes memory payload = abi.encodeWithSignature(
                "executeChainEmergency(bytes32,uint256,bytes)",
                coordination.coordinationHash,
                chainId,
                ""
            );

            // Get target contract address for the chain
            uint256[] memory supportedChains = crossChainManager.getSupportedChains();
            address targetContract = address(0);
            
            // In a real implementation, you would have a mapping of chain contracts
            // For now, we'll use a placeholder
            
            ILitRelayContract.CrossChainMessage memory message = ILitRelayContract.CrossChainMessage({
                sourceChainId: block.chainid,
                targetChainId: chainId,
                sourceContract: address(this),
                targetContract: targetContract,
                payload: payload,
                nonce: block.timestamp,
                timestamp: block.timestamp
            });

            // Send message through Lit Relay Contract
            litRelayContract.sendCrossChainMessage(message);
        }
    }

    /**
     * @dev Internal function to execute governance on specific chain
     */
    function _executeGovernanceOnChain(uint256 chainId, bytes memory executionData) internal {
        // In a real implementation, this would send cross-chain messages
        // to execute governance actions on the target chain
        
        // For now, we'll emit an event
        emit CrossChainGovernanceExecuted(
            keccak256(executionData),
            _toSingleElementArray(chainId),
            true
        );
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
     * @dev Helper function to create single element array
     */
    function _toSingleElementArray(uint256 element) internal pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;
        return array;
    }

    /**
     * @dev Get user's emergency hashes
     * @param user User address
     * @return bytes32[] Array of emergency hashes
     */
    function getUserEmergencyHashes(address user) external view returns (bytes32[] memory) {
        return userEmergencyHashes[user];
    }

    /**
     * @dev Check if chain is paused
     * @param chainId Chain ID
     * @return bool True if paused
     */
    function isChainPaused(uint256 chainId) external view returns (bool) {
        return chainsPaused[chainId];
    }

    /**
     * @dev Check if address is governance member
     * @param member Address to check
     * @return bool True if governance member
     */
    function isGovernanceMember(address member) external view returns (bool) {
        return governanceMembers[member];
    }
}