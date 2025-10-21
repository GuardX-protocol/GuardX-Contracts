// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ICrashGuardCore.sol";
import "./interfaces/IDEXAggregator.sol";
import "./interfaces/IPythPriceMonitor.sol";

contract PortfolioRebalancer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ICrashGuardCore public crashGuardCore;
    IDEXAggregator public dexAggregator;
    IPythPriceMonitor public priceMonitor;

    struct RebalanceStrategy {
        address[] targetTokens;
        uint256[] targetAllocations;
        uint256 rebalanceThreshold;
        uint256 minRebalanceInterval;
        bool autoRebalance;
    }

    struct AllocationTarget {
        address token;
        uint256 targetPercentage;
        uint256 currentPercentage;
        int256 rebalanceAmount;
    }

    mapping(address => RebalanceStrategy) public userStrategies;
    mapping(address => uint256) public lastRebalanceTime;
    mapping(address => bool) public authorizedRebalancers;

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_REBALANCE_THRESHOLD = 100;
    uint256 public constant MAX_REBALANCE_THRESHOLD = 5000;
    uint256 public constant MIN_INTERVAL = 1 hours;

    event StrategySet(address indexed user, address[] tokens, uint256[] allocations);
    event RebalanceExecuted(address indexed user, uint256 timestamp, uint256 totalValue);
    event AllocationAdjusted(address indexed user, address token, int256 amount);

    constructor(
        address _crashGuardCore,
        address _dexAggregator,
        address _priceMonitor
    ) {
        require(_crashGuardCore != address(0), "Invalid core");
        require(_dexAggregator != address(0), "Invalid dex");
        require(_priceMonitor != address(0), "Invalid monitor");

        crashGuardCore = ICrashGuardCore(_crashGuardCore);
        dexAggregator = IDEXAggregator(_dexAggregator);
        priceMonitor = IPythPriceMonitor(_priceMonitor);

        authorizedRebalancers[msg.sender] = true;
    }

    modifier onlyAuthorized() {
        require(authorizedRebalancers[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    function setRebalanceStrategy(
        address[] calldata targetTokens,
        uint256[] calldata targetAllocations,
        uint256 rebalanceThreshold,
        uint256 minRebalanceInterval,
        bool autoRebalance
    ) external {
        require(targetTokens.length > 0, "Empty tokens");
        require(targetTokens.length == targetAllocations.length, "Length mismatch");
        require(rebalanceThreshold >= MIN_REBALANCE_THRESHOLD, "Threshold too low");
        require(rebalanceThreshold <= MAX_REBALANCE_THRESHOLD, "Threshold too high");
        require(minRebalanceInterval >= MIN_INTERVAL, "Interval too short");

        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < targetAllocations.length; i++) {
            totalAllocation += targetAllocations[i];
        }
        require(totalAllocation == BASIS_POINTS, "Must equal 100%");

        userStrategies[msg.sender] = RebalanceStrategy({
            targetTokens: targetTokens,
            targetAllocations: targetAllocations,
            rebalanceThreshold: rebalanceThreshold,
            minRebalanceInterval: minRebalanceInterval,
            autoRebalance: autoRebalance
        });

        emit StrategySet(msg.sender, targetTokens, targetAllocations);
    }

    function executeRebalance(address user) external onlyAuthorized nonReentrant {
        RebalanceStrategy memory strategy = userStrategies[user];
        require(strategy.targetTokens.length > 0, "No strategy");
        require(
            block.timestamp >= lastRebalanceTime[user] + strategy.minRebalanceInterval,
            "Too soon"
        );

        ICrashGuardCore.Portfolio memory portfolio = crashGuardCore.getUserPortfolio(user);
        require(portfolio.assets.length > 0, "No assets");

        AllocationTarget[] memory targets = _calculateRebalanceTargets(user, portfolio, strategy);
        
        bool needsRebalance = false;
        for (uint256 i = 0; i < targets.length; i++) {
            uint256 deviation = targets[i].currentPercentage > targets[i].targetPercentage ?
                targets[i].currentPercentage - targets[i].targetPercentage :
                targets[i].targetPercentage - targets[i].currentPercentage;
            
            if (deviation >= strategy.rebalanceThreshold) {
                needsRebalance = true;
                break;
            }
        }

        require(needsRebalance, "No rebalance needed");

        _executeRebalanceSwaps(user, targets, portfolio.totalValue);

        lastRebalanceTime[user] = block.timestamp;
        emit RebalanceExecuted(user, block.timestamp, portfolio.totalValue);
    }

    function checkRebalanceNeeded(address user) external view returns (bool needed, uint256 maxDeviation) {
        RebalanceStrategy memory strategy = userStrategies[user];
        if (strategy.targetTokens.length == 0) return (false, 0);
        if (block.timestamp < lastRebalanceTime[user] + strategy.minRebalanceInterval) return (false, 0);

        ICrashGuardCore.Portfolio memory portfolio = crashGuardCore.getUserPortfolio(user);
        if (portfolio.assets.length == 0) return (false, 0);

        AllocationTarget[] memory targets = _calculateRebalanceTargets(user, portfolio, strategy);

        for (uint256 i = 0; i < targets.length; i++) {
            uint256 deviation = targets[i].currentPercentage > targets[i].targetPercentage ?
                targets[i].currentPercentage - targets[i].targetPercentage :
                targets[i].targetPercentage - targets[i].currentPercentage;
            
            if (deviation > maxDeviation) {
                maxDeviation = deviation;
            }
            
            if (deviation >= strategy.rebalanceThreshold) {
                needed = true;
            }
        }
    }

    function getRebalanceTargets(address user) external view returns (AllocationTarget[] memory) {
        RebalanceStrategy memory strategy = userStrategies[user];
        require(strategy.targetTokens.length > 0, "No strategy");

        ICrashGuardCore.Portfolio memory portfolio = crashGuardCore.getUserPortfolio(user);
        require(portfolio.assets.length > 0, "No assets");

        return _calculateRebalanceTargets(user, portfolio, strategy);
    }

    function _calculateRebalanceTargets(
        address user,
        ICrashGuardCore.Portfolio memory portfolio,
        RebalanceStrategy memory strategy
    ) internal view returns (AllocationTarget[] memory) {
        AllocationTarget[] memory targets = new AllocationTarget[](strategy.targetTokens.length);

        uint256 totalValue = portfolio.totalValue;
        if (totalValue == 0) {
            totalValue = _calculateTotalValue(portfolio);
        }

        for (uint256 i = 0; i < strategy.targetTokens.length; i++) {
            address token = strategy.targetTokens[i];
            uint256 targetPercentage = strategy.targetAllocations[i];
            
            uint256 currentValue = 0;
            for (uint256 j = 0; j < portfolio.assets.length; j++) {
                if (portfolio.assets[j].tokenAddress == token) {
                    currentValue = portfolio.assets[j].valueUSD;
                    break;
                }
            }

            uint256 currentPercentage = totalValue > 0 ? (currentValue * BASIS_POINTS) / totalValue : 0;
            uint256 targetValue = (totalValue * targetPercentage) / BASIS_POINTS;
            int256 rebalanceAmount = int256(targetValue) - int256(currentValue);

            targets[i] = AllocationTarget({
                token: token,
                targetPercentage: targetPercentage,
                currentPercentage: currentPercentage,
                rebalanceAmount: rebalanceAmount
            });
        }

        return targets;
    }

    function _executeRebalanceSwaps(
        address user,
        AllocationTarget[] memory targets,
        uint256 totalValue
    ) internal {
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i].rebalanceAmount == 0) continue;

            if (targets[i].rebalanceAmount > 0) {
                _buyToken(user, targets[i], totalValue);
            } else {
                _sellToken(user, targets[i]);
            }

            emit AllocationAdjusted(user, targets[i].token, targets[i].rebalanceAmount);
        }
    }

    function _buyToken(
        address user,
        AllocationTarget memory target,
        uint256 totalValue
    ) internal {
        address[] memory sellTokens = _findTokensToSell(user, uint256(target.rebalanceAmount));
        
        for (uint256 i = 0; i < sellTokens.length; i++) {
            if (sellTokens[i] == target.token) continue;

            uint256 sellAmount = crashGuardCore.getUserBalance(user, sellTokens[i]);
            if (sellAmount == 0) continue;

            crashGuardCore.emergencyWithdraw(user, sellTokens[i], sellAmount);

            IERC20(sellTokens[i]).forceApprove(address(dexAggregator), sellAmount);

            try dexAggregator.swapTokens(
                sellTokens[i],
                target.token,
                sellAmount,
                500,
                block.timestamp + 300
            ) returns (uint256 amountOut, uint256) {
                IERC20(target.token).forceApprove(address(crashGuardCore), amountOut);
            } catch {}
        }
    }

    function _sellToken(
        address user,
        AllocationTarget memory target
    ) internal {
        uint256 sellAmount = uint256(-target.rebalanceAmount);
        uint256 balance = crashGuardCore.getUserBalance(user, target.token);
        
        if (balance < sellAmount) {
            sellAmount = balance;
        }

        if (sellAmount == 0) return;

        crashGuardCore.emergencyWithdraw(user, target.token, sellAmount);

        address buyToken = _findBestBuyToken(user);
        if (buyToken == address(0)) return;

        IERC20(target.token).forceApprove(address(dexAggregator), sellAmount);

        try dexAggregator.swapTokens(
            target.token,
            buyToken,
            sellAmount,
            500,
            block.timestamp + 300
        ) returns (uint256 amountOut, uint256) {
            IERC20(buyToken).forceApprove(address(crashGuardCore), amountOut);
        } catch {}
    }

    function _findTokensToSell(address user, uint256 targetValue) internal view returns (address[] memory) {
        ICrashGuardCore.Portfolio memory portfolio = crashGuardCore.getUserPortfolio(user);
        address[] memory tokens = new address[](portfolio.assets.length);
        uint256 count = 0;

        for (uint256 i = 0; i < portfolio.assets.length; i++) {
            if (portfolio.assets[i].amount > 0) {
                tokens[count] = portfolio.assets[i].tokenAddress;
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tokens[i];
        }

        return result;
    }

    function _findBestBuyToken(address user) internal view returns (address) {
        RebalanceStrategy memory strategy = userStrategies[user];
        if (strategy.targetTokens.length == 0) return address(0);

        return strategy.targetTokens[0];
    }

    function _calculateTotalValue(ICrashGuardCore.Portfolio memory portfolio) internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < portfolio.assets.length; i++) {
            total += portfolio.assets[i].valueUSD;
        }
        return total;
    }

    function setAuthorizedRebalancer(address rebalancer, bool authorized) external onlyOwner {
        require(rebalancer != address(0), "Invalid address");
        authorizedRebalancers[rebalancer] = authorized;
    }

    function updateContracts(
        address _crashGuardCore,
        address _dexAggregator,
        address _priceMonitor
    ) external onlyOwner {
        if (_crashGuardCore != address(0)) crashGuardCore = ICrashGuardCore(_crashGuardCore);
        if (_dexAggregator != address(0)) dexAggregator = IDEXAggregator(_dexAggregator);
        if (_priceMonitor != address(0)) priceMonitor = IPythPriceMonitor(_priceMonitor);
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
