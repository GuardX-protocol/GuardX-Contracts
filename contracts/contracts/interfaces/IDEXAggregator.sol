// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDEXAggregator
 * @dev Interface for DEX aggregation and optimal routing
 */
interface IDEXAggregator {
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address recipient;
        uint256 deadline;
    }

    struct RouteInfo {
        address[] path;
        address[] exchanges;
        uint256[] fees;
        uint256 expectedOutput;
        uint256 gasEstimate;
    }

    struct MEVProtectionConfig {
        bool usePrivateMempool;
        uint256 maxPriorityFee;
        uint256 commitRevealDelay;
    }

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );
    event RouteOptimized(address tokenIn, address tokenOut, RouteInfo route);

    function getOptimalRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (RouteInfo memory);
    
    function executeSwap(SwapParams calldata params) external returns (uint256 amountOut);
    function executeSwapWithMEVProtection(
        SwapParams calldata params,
        MEVProtectionConfig calldata mevConfig
    ) external returns (uint256 amountOut);
    function batchSwaps(SwapParams[] calldata swaps) external returns (uint256[] memory amountsOut);
    // Emergency swap function for EmergencyExecutor
    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 maxSlippage,
        uint256 deadline
    ) external returns (uint256 amountOut, uint256 actualSlippage);
}