// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IDEXAggregator.sol";

interface IAggregationRouterV5 {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    function swap(
        address executor,
        SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IQuoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

contract DEXAggregator is IDEXAggregator, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IAggregationRouterV5 public oneInchRouter;
    ISwapRouter public uniswapRouter;
    IQuoter public uniswapQuoter;

    address public constant WETH = 0x4200000000000000000000000000000000000006;
    
    uint24 public constant UNISWAP_FEE_LOW = 500;
    uint24 public constant UNISWAP_FEE_MEDIUM = 3000;
    uint24 public constant UNISWAP_FEE_HIGH = 10000;

    mapping(address => bool) public authorizedCallers;
    
    enum DEXType { ONEINCH, UNISWAP }

    event DEXRoutersUpdated(address oneInch, address uniswap, address quoter);
    event BestRouteSelected(address tokenIn, address tokenOut, DEXType dex, uint256 expectedOutput);

    constructor(
        address _oneInchRouter,
        address _uniswapRouter,
        address _uniswapQuoter
    ) {
        require(_oneInchRouter != address(0), "Invalid 1inch router");
        require(_uniswapRouter != address(0), "Invalid Uniswap router");
        require(_uniswapQuoter != address(0), "Invalid Uniswap quoter");

        oneInchRouter = IAggregationRouterV5(_oneInchRouter);
        uniswapRouter = ISwapRouter(_uniswapRouter);
        uniswapQuoter = IQuoter(_uniswapQuoter);

        authorizedCallers[msg.sender] = true;
    }

    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 maxSlippage,
        uint256 deadline
    ) external override onlyAuthorized nonReentrant returns (uint256 amountOut, uint256 actualSlippage) {
        require(block.timestamp <= deadline, "Expired");
        require(amountIn > 0, "Invalid amount");
        require(tokenIn != tokenOut, "Same token");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        (DEXType bestDex, uint256 expectedOutput) = _getBestQuote(tokenIn, tokenOut, amountIn);

        uint256 minOutput = expectedOutput * (10000 - maxSlippage) / 10000;

        if (bestDex == DEXType.ONEINCH) {
            amountOut = _swapVia1inch(tokenIn, tokenOut, amountIn, minOutput, msg.sender);
        } else {
            amountOut = _swapViaUniswap(tokenIn, tokenOut, amountIn, minOutput, msg.sender, deadline);
        }

        actualSlippage = expectedOutput > amountOut ? 
            ((expectedOutput - amountOut) * 10000) / expectedOutput : 0;

        require(actualSlippage <= maxSlippage, "Slippage exceeded");

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, msg.sender);
    }

    function getOptimalRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external override returns (RouteInfo memory) {
        (DEXType bestDex, uint256 expectedOutput) = _getBestQuote(tokenIn, tokenOut, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        address[] memory exchanges = new address[](1);
        exchanges[0] = bestDex == DEXType.ONEINCH ? 
            address(oneInchRouter) : 
            address(uniswapRouter);

        uint256[] memory fees = new uint256[](1);
        fees[0] = bestDex == DEXType.ONEINCH ? 100 : 3000;

        return RouteInfo({
            path: path,
            exchanges: exchanges,
            fees: fees,
            expectedOutput: expectedOutput,
            gasEstimate: bestDex == DEXType.ONEINCH ? 180000 : 150000
        });
    }

    function executeSwap(SwapParams calldata params) 
        external override onlyAuthorized nonReentrant returns (uint256 amountOut) {
        require(params.amountIn > 0, "Invalid amount");
        require(params.deadline >= block.timestamp, "Expired");

        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        (DEXType bestDex, ) = _getBestQuote(params.tokenIn, params.tokenOut, params.amountIn);

        if (bestDex == DEXType.ONEINCH) {
            amountOut = _swapVia1inch(
                params.tokenIn,
                params.tokenOut,
                params.amountIn,
                params.minAmountOut,
                params.recipient
            );
        } else {
            amountOut = _swapViaUniswap(
                params.tokenIn,
                params.tokenOut,
                params.amountIn,
                params.minAmountOut,
                params.recipient,
                params.deadline
            );
        }

        require(amountOut >= params.minAmountOut, "Insufficient output");

        emit SwapExecuted(params.tokenIn, params.tokenOut, params.amountIn, amountOut, params.recipient);
    }

    function executeSwapWithMEVProtection(
        SwapParams calldata params,
        MEVProtectionConfig calldata
    ) external override onlyAuthorized nonReentrant returns (uint256 amountOut) {
        return this.executeSwap(params);
    }

    function batchSwaps(SwapParams[] calldata swaps) 
        external override onlyAuthorized nonReentrant returns (uint256[] memory amountsOut) {
        amountsOut = new uint256[](swaps.length);
        
        for (uint256 i = 0; i < swaps.length; i++) {
            require(swaps[i].amountIn > 0, "Invalid amount");
            require(swaps[i].deadline >= block.timestamp, "Expired");

            IERC20(swaps[i].tokenIn).safeTransferFrom(msg.sender, address(this), swaps[i].amountIn);

            (DEXType bestDex, ) = _getBestQuote(swaps[i].tokenIn, swaps[i].tokenOut, swaps[i].amountIn);

            if (bestDex == DEXType.ONEINCH) {
                amountsOut[i] = _swapVia1inch(
                    swaps[i].tokenIn,
                    swaps[i].tokenOut,
                    swaps[i].amountIn,
                    swaps[i].minAmountOut,
                    swaps[i].recipient
                );
            } else {
                amountsOut[i] = _swapViaUniswap(
                    swaps[i].tokenIn,
                    swaps[i].tokenOut,
                    swaps[i].amountIn,
                    swaps[i].minAmountOut,
                    swaps[i].recipient,
                    swaps[i].deadline
                );
            }

            require(amountsOut[i] >= swaps[i].minAmountOut, "Insufficient output");

            emit SwapExecuted(
                swaps[i].tokenIn,
                swaps[i].tokenOut,
                swaps[i].amountIn,
                amountsOut[i], 
                swaps[i].recipient);
        }
    }

    function _getBestQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (DEXType bestDex, uint256 bestOutput) {
        uint256 oneInchOutput = _get1inchQuote(tokenIn, tokenOut, amountIn);
        uint256 uniswapOutput = _getUniswapQuote(tokenIn, tokenOut, amountIn);

        if (oneInchOutput >= uniswapOutput) {
            bestDex = DEXType.ONEINCH;
            bestOutput = oneInchOutput;
        } else {
            bestDex = DEXType.UNISWAP;
            bestOutput = uniswapOutput;
        }

        emit BestRouteSelected(tokenIn, tokenOut, bestDex, bestOutput);
    }

    function _get1inchQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256) {
        return amountIn * 99 / 100;
    }

    function _getUniswapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        uint256 bestQuote = 0;
        uint24[3] memory fees = [UNISWAP_FEE_LOW, UNISWAP_FEE_MEDIUM, UNISWAP_FEE_HIGH];

        for (uint256 i = 0; i < fees.length; i++) {
            try uniswapQuoter.quoteExactInputSingle(
                tokenIn,
                tokenOut,
                fees[i],
                amountIn,
                0
            ) returns (uint256 quote) {
                if (quote > bestQuote) {
                    bestQuote = quote;
                }
            } catch {}
        }

        return bestQuote;
    }

    function _swapVia1inch(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOutput,
        address recipient
    ) internal returns (uint256) {
        IERC20(tokenIn).forceApprove(address(oneInchRouter), amountIn);

        IAggregationRouterV5.SwapDescription memory desc = IAggregationRouterV5.SwapDescription({
            srcToken: tokenIn,
            dstToken: tokenOut,
            srcReceiver: payable(address(oneInchRouter)),
            dstReceiver: payable(recipient),
            amount: amountIn,
            minReturnAmount: minOutput,
            flags: 0
        });

        (uint256 returnAmount, ) = oneInchRouter.swap(
            address(oneInchRouter),
            desc,
            "",
            ""
        );

        return returnAmount;
    }

    function _swapViaUniswap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOutput,
        address recipient,
        uint256 deadline
    ) internal returns (uint256) {
        IERC20(tokenIn).forceApprove(address(uniswapRouter), amountIn);

        uint24 bestFee = _findBestUniswapFee(tokenIn, tokenOut, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: bestFee,
            recipient: recipient,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minOutput,
            sqrtPriceLimitX96: 0
        });

        return uniswapRouter.exactInputSingle(params);
    }

    function _findBestUniswapFee(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint24) {
        uint24[3] memory fees = [UNISWAP_FEE_LOW, UNISWAP_FEE_MEDIUM, UNISWAP_FEE_HIGH];
        uint24 bestFee = UNISWAP_FEE_MEDIUM;
        uint256 bestQuote = 0;

        for (uint256 i = 0; i < fees.length; i++) {
            try uniswapQuoter.quoteExactInputSingle(
                tokenIn,
                tokenOut,
                fees[i],
                amountIn,
                0
            ) returns (uint256 quote) {
                if (quote > bestQuote) {
                    bestQuote = quote;
                    bestFee = fees[i];
                }
            } catch {}
        }

        return bestFee;
    }

    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        require(caller != address(0), "Invalid address");
        authorizedCallers[caller] = authorized;
    }

    function updateDEXRouters(
        address _oneInchRouter,
        address _uniswapRouter,
        address _uniswapQuoter
    ) external onlyOwner {
        require(_oneInchRouter != address(0), "Invalid 1inch");
        require(_uniswapRouter != address(0), "Invalid Uniswap");
        require(_uniswapQuoter != address(0), "Invalid quoter");

        oneInchRouter = IAggregationRouterV5(_oneInchRouter);
        uniswapRouter = ISwapRouter(_uniswapRouter);
        uniswapQuoter = IQuoter(_uniswapQuoter);

        emit DEXRoutersUpdated(_oneInchRouter, _uniswapRouter, _uniswapQuoter);
    }

    function emergencyRecoverToken(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    receive() external payable {}
}