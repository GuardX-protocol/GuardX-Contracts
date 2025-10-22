// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ICrashGuardCore.sol";

/**
 * @title SimpleCrossChainBridge
 * @notice Simple bridge contract for cross-chain deposits to CrashGuard
 * @dev This is a simplified example - production bridges would use proper cross-chain protocols
 */
contract SimpleCrossChainBridge is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // CrashGuard contract on destination chain
    ICrashGuardCore public crashGuardCore;

    // Chain ID mapping
    mapping(uint256 => bool) public supportedChains;

    // Relayer authorization
    mapping(address => bool) public authorizedRelayers;

    // Processed deposits to prevent replay
    mapping(bytes32 => bool) public processedDeposits;

    // Events
    event CrossChainDepositInitiated(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 indexed destinationChain,
        bytes32 depositHash
    );

    event CrossChainDepositCompleted(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 indexed sourceChain,
        bytes32 depositHash
    );

    event RelayerUpdated(address indexed relayer, bool authorized);
    event ChainSupportUpdated(uint256 indexed chainId, bool supported);

    modifier onlyRelayer() {
        require(authorizedRelayers[msg.sender], "Not authorized relayer");
        _;
    }

    constructor(address _crashGuardCore) {
        require(_crashGuardCore != address(0), "Invalid CrashGuard address");
        crashGuardCore = ICrashGuardCore(_crashGuardCore);
    }

    /**
     * @dev Initiate cross-chain deposit
     * @param token Token address on source chain
     * @param amount Amount to bridge
     * @param destinationChain Target chain ID
     * @param destinationUser User address on destination chain
     */
    function initiateCrossChainDeposit(
        address token,
        uint256 amount,
        uint256 destinationChain,
        address destinationUser
    ) external payable nonReentrant {
        require(supportedChains[destinationChain], "Chain not supported");
        require(destinationUser != address(0), "Invalid destination user");
        require(amount > 0, "Amount must be positive");

        // Generate unique deposit hash
        bytes32 depositHash = keccak256(
            abi.encodePacked(
                msg.sender,
                token,
                amount,
                destinationChain,
                destinationUser,
                block.timestamp,
                block.number
            )
        );

        if (token == address(0)) {
            // ETH deposit
            require(msg.value == amount, "ETH amount mismatch");
        } else {
            // ERC20 deposit
            require(msg.value == 0, "ETH not expected for ERC20");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit CrossChainDepositInitiated(
            destinationUser,
            token,
            amount,
            destinationChain,
            depositHash
        );

        // In a real bridge, this would trigger cross-chain message
        // For this example, relayers will pick up the event and complete on destination
    }

    /**
     * @dev Complete cross-chain deposit (called by relayer on destination chain)
     * @param user User address on destination chain
     * @param token Token address on destination chain
     * @param amount Amount to deposit
     * @param sourceChain Source chain ID
     * @param depositHash Unique deposit hash from source
     */
    function completeCrossChainDeposit(
        address user,
        address token,
        uint256 amount,
        uint256 sourceChain,
        bytes32 depositHash
    ) external onlyRelayer nonReentrant {
        require(!processedDeposits[depositHash], "Deposit already processed");
        require(supportedChains[sourceChain], "Source chain not supported");

        // Mark as processed
        processedDeposits[depositHash] = true;

        // Complete deposit to CrashGuard
        crashGuardCore.crossChainDeposit(
            user,
            token,
            amount,
            sourceChain,
            depositHash
        );

        emit CrossChainDepositCompleted(
            user,
            token,
            amount,
            sourceChain,
            depositHash
        );
    }

    /**
     * @dev Set relayer authorization
     * @param relayer Relayer address
     * @param authorized True to authorize, false to revoke
     */
    function setRelayerAuthorization(
        address relayer,
        bool authorized
    ) external onlyOwner {
        require(relayer != address(0), "Invalid relayer address");
        authorizedRelayers[relayer] = authorized;
        emit RelayerUpdated(relayer, authorized);
    }

    /**
     * @dev Set chain support
     * @param chainId Chain ID
     * @param supported True to support, false to remove support
     */
    function setChainSupport(
        uint256 chainId,
        bool supported
    ) external onlyOwner {
        require(chainId != 0, "Invalid chain ID");
        supportedChains[chainId] = supported;
        emit ChainSupportUpdated(chainId, supported);
    }

    /**
     * @dev Update CrashGuard contract address
     * @param _crashGuardCore New CrashGuard address
     */
    function setCrashGuardCore(address _crashGuardCore) external onlyOwner {
        require(_crashGuardCore != address(0), "Invalid address");
        crashGuardCore = ICrashGuardCore(_crashGuardCore);
    }

    /**
     * @dev Emergency withdrawal (owner only)
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /**
     * @dev Check if deposit was processed
     * @param depositHash Deposit hash
     * @return bool True if processed
     */
    function isDepositProcessed(
        bytes32 depositHash
    ) external view returns (bool) {
        return processedDeposits[depositHash];
    }

    receive() external payable {
        // Allow contract to receive ETH
    }
}
