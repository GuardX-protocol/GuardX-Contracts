// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICrossChainEmergencyCoordinator
 * @dev Interface for coordinating emergency actions across multiple chains
 */
interface ICrossChainEmergencyCoordinator {
    struct EmergencyCoordination {
        address user;
        uint256[] chainIds;
        string[] litActionIds;
        bytes32 coordinationHash;
        uint256 timestamp;
        bool executed;
        uint256 executedChains;
    }

    struct ChainEmergencyStatus {
        uint256 chainId;
        bool emergencyActive;
        uint256 lastExecution;
        uint256 executionCount;
        bytes32 lastExecutionHash;
    }

    struct CrossChainGovernance {
        bytes32 proposalHash;
        string description;
        uint256[] targetChains;
        bytes[] executionData;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 deadline;
        bool executed;
    }

    event CrossChainEmergencyInitiated(
        address indexed user,
        bytes32 indexed coordinationHash,
        uint256[] chainIds,
        uint256 timestamp
    );

    event CrossChainEmergencyExecuted(
        address indexed user,
        bytes32 indexed coordinationHash,
        uint256 indexed chainId,
        bool success
    );

    event CrossChainEmergencyCompleted(
        address indexed user,
        bytes32 indexed coordinationHash,
        uint256 successfulChains,
        uint256 totalChains
    );

    event CrossChainGovernanceProposal(
        bytes32 indexed proposalHash,
        uint256[] targetChains,
        uint256 deadline
    );

    event CrossChainGovernanceExecuted(
        bytes32 indexed proposalHash,
        uint256[] executedChains,
        bool success
    );

    function initiateMultiChainEmergency(
        address user,
        uint256[] calldata chainIds,
        string[] calldata litActionIds
    ) external returns (bytes32);

    function executeChainEmergency(
        bytes32 coordinationHash,
        uint256 chainId,
        bytes calldata signature
    ) external returns (bool);

    function getEmergencyCoordination(
        bytes32 coordinationHash
    ) external view returns (EmergencyCoordination memory);

    function getChainEmergencyStatus(
        uint256 chainId
    ) external view returns (ChainEmergencyStatus memory);

    function isEmergencyActive(uint256 chainId) external view returns (bool);

    function proposeGovernanceAction(
        string calldata description,
        uint256[] calldata targetChains,
        bytes[] calldata executionData
    ) external returns (bytes32);

    function voteOnGovernanceProposal(
        bytes32 proposalHash,
        bool support
    ) external;

    function executeGovernanceProposal(
        bytes32 proposalHash
    ) external returns (bool);

    function emergencyPauseChain(uint256 chainId) external;

    function emergencyResumeChain(uint256 chainId) external;
}