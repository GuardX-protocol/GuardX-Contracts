// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IPythPriceMonitor.sol";

/**
 * @title PythPriceMonitor - Real-time Price Monitoring with Pyth Network
 * @notice Fetches and monitors real-time price data from Pyth Network
 * @dev Supports both real-time updates via Hermes API and reading cached prices
 */
contract PythPriceMonitor is IPythPriceMonitor, Ownable, ReentrancyGuard {
    IPyth public immutable PYTH;
    
    // Price data storage
    mapping(bytes32 => PriceData) private latestPrices;
    mapping(bytes32 => PriceData[]) private priceHistory;
    mapping(bytes32 => address) public priceIdToToken;
    mapping(address => bytes32) public tokenToPriceId;
    
    // Crash detection parameters
    uint256 private constant MAX_PRICE_AGE = 300; // 5 minutes
    uint256 private constant REALTIME_MAX_AGE = 60; // 60 seconds for real-time
    uint256 private constant HISTORY_LIMIT = 100;
    uint256 private constant PRECISION = 1e8;
    
    // Emergency controls
    bool public emergencyPaused = false;
    address public crashGuardCore;
    
    // Events
    event PricesUpdatedRealtime(uint256 timestamp);
    event PriceFeedAdded(bytes32 indexed priceId, address indexed token);
    event PriceFeedRemoved(bytes32 indexed priceId);
    
    modifier notPaused() {
        require(!emergencyPaused, "Contract is paused");
        _;
    }
    
    modifier onlyCrashGuard() {
        require(msg.sender == crashGuardCore, "Only CrashGuard can call");
        _;
    }
    
    constructor(address _pythContract) {
        require(_pythContract != address(0), "Invalid Pyth contract");
        PYTH = IPyth(_pythContract);
    }
    
    /**
     * @dev Update prices with real-time data from Pyth Hermes API
     * @param priceUpdateData Signed price update data from Hermes
     * @notice Call this with data from: https://hermes.pyth.network/api/latest_vaas?ids[]=<price_id>
     */
    function updatePricesRealtime(bytes[] calldata priceUpdateData) 
        external 
        payable 
        nonReentrant 
        notPaused 
    {
        require(priceUpdateData.length > 0, "No price update data");
        
        // Get required fee for update
        uint256 updateFee = PYTH.getUpdateFee(priceUpdateData);
        require(msg.value >= updateFee, "Insufficient fee");
        
        // Update Pyth contract with real-time data
        PYTH.updatePriceFeeds{value: updateFee}(priceUpdateData);
        
        // Refund excess
        if (msg.value > updateFee) {
            payable(msg.sender).transfer(msg.value - updateFee);
        }
        
        emit PricesUpdatedRealtime(block.timestamp);
    }
    
    /**
     * @dev Update prices (legacy interface compatibility)
     * @param priceIds Array of price feed IDs to update
     */
    function updatePrices(bytes32[] calldata priceIds) 
        external 
        payable 
        nonReentrant 
        notPaused 
    {
        // Refund any ETH sent (not needed for reading)
        if (msg.value > 0) {
            payable(msg.sender).transfer(msg.value);
        }
        
        // Read latest prices
        _readLatestPrices(priceIds);
    }
    
    /**
     * @dev Read and cache latest prices from Pyth
     * @param priceIds Price feed IDs to read
     */
    function readLatestPrices(bytes32[] calldata priceIds) 
        external 
        nonReentrant 
        notPaused 
    {
        _readLatestPrices(priceIds);
    }
    
    /**
     * @dev Internal function to read and cache prices
     * @param priceIds Price feed IDs to read
     */
    function _readLatestPrices(bytes32[] calldata priceIds) 
        private 
    {
        require(priceIds.length > 0, "No price IDs");
        
        uint256 successCount = 0;
        for (uint256 i = 0; i < priceIds.length; i++) {
            try PYTH.getPriceNoOlderThan(priceIds[i], REALTIME_MAX_AGE) returns (
                PythStructs.Price memory price
            ) {
                _storePriceData(priceIds[i], price);
                successCount++;
            } catch {
                // Fallback to slightly older data
                try PYTH.getPriceNoOlderThan(priceIds[i], MAX_PRICE_AGE) returns (
                    PythStructs.Price memory price
                ) {
                    _storePriceData(priceIds[i], price);
                    successCount++;
                } catch {
                    continue;
                }
            }
        }
        
        require(successCount > 0, "No prices updated");
        emit PricesUpdated(priceIds, block.timestamp);
    }
    
    /**
     * @dev Get real-time price directly from Pyth
     * @param priceId Price feed ID
     * @return PriceData Real-time price
     */
    function getRealtimePrice(bytes32 priceId) 
        external 
        view 
        returns (PriceData memory) 
    {
        PythStructs.Price memory pythPrice = PYTH.getPriceNoOlderThan(priceId, REALTIME_MAX_AGE);
        
        return PriceData({
            price: _convertPythPrice(pythPrice.price, pythPrice.expo),
            timestamp: block.timestamp,
            confidence: _convertPythPrice(int64(pythPrice.conf), pythPrice.expo),
            isValid: pythPrice.price > 0
        });
    }
    
    /**
     * @dev Get latest cached price
     * @param priceId Price feed ID
     * @return PriceData Latest cached price
     */
    function getLatestPrice(bytes32 priceId) 
        external 
        view 
        returns (PriceData memory) 
    {
        PriceData memory priceData = latestPrices[priceId];
        require(priceData.timestamp > 0, "Price not available");
        
        if (block.timestamp - priceData.timestamp > MAX_PRICE_AGE) {
            priceData.isValid = false;
        }
        
        return priceData;
    }
    
    /**
     * @dev Get update fee for real-time updates
     * @param priceUpdateData Price update data
     * @return Fee in wei
     */
    function getUpdateFee(bytes[] calldata priceUpdateData) 
        external 
        view 
        returns (uint256) 
    {
        return PYTH.getUpdateFee(priceUpdateData);
    }
    
    /**
     * @dev Detect multi-asset crash
     * @param thresholds Crash detection parameters
     * @return True if crash detected
     */
    function detectMultiAssetCrash(CrashThresholds memory thresholds) 
        external 
        view 
        returns (bool) 
    {
        require(thresholds.singleAssetThreshold > 0, "Invalid threshold");
        require(thresholds.multiAssetThreshold > 0, "Invalid multi threshold");
        require(thresholds.timeWindow > 0, "Invalid time window");
        require(thresholds.minimumAssets >= 2, "Min assets must be >= 2");
        
        uint256 crashedAssets = 0;
        uint256 totalAssets = 0;
        
        bytes32[] memory monitoredPriceIds = _getMonitoredPriceIds();
        
        for (uint256 i = 0; i < monitoredPriceIds.length; i++) {
            bytes32 priceId = monitoredPriceIds[i];
            PriceData memory currentPrice = latestPrices[priceId];
            
            if (!currentPrice.isValid || 
                block.timestamp - currentPrice.timestamp > MAX_PRICE_AGE) {
                continue;
            }
            
            totalAssets++;
            
            PriceData memory historicalPrice = _getHistoricalPrice(priceId, thresholds.timeWindow);
            
            if (historicalPrice.timestamp > 0) {
                uint256 priceChange = _calculatePriceChange(historicalPrice.price, currentPrice.price);
                
                if (priceChange >= thresholds.singleAssetThreshold) {
                    crashedAssets++;
                }
            }
        }
        
        if (totalAssets >= thresholds.minimumAssets && crashedAssets >= thresholds.minimumAssets) {
            uint256 crashPercentage = (crashedAssets * 10000) / totalAssets;
            return crashPercentage >= thresholds.multiAssetThreshold;
        }
        
        return false;
    }
    
    /**
     * @dev Get price history
     * @param priceId Price feed ID
     * @param timeRange Time range in seconds
     * @return Historical prices
     */
    function getPriceHistory(bytes32 priceId, uint256 timeRange) 
        external 
        view 
        returns (PriceData[] memory) 
    {
        require(timeRange > 0, "Invalid time range");
        
        PriceData[] storage history = priceHistory[priceId];
        uint256 cutoffTime = block.timestamp - timeRange;
        
        uint256 validCount = 0;
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].timestamp >= cutoffTime) {
                validCount++;
            }
        }
        
        PriceData[] memory result = new PriceData[](validCount);
        uint256 resultIndex = 0;
        
        for (uint256 i = 0; i < history.length && resultIndex < validCount; i++) {
            if (history[i].timestamp >= cutoffTime) {
                result[resultIndex] = history[i];
                resultIndex++;
            }
        }
        
        return result;
    }
    
    /**
     * @dev Add price feed to monitor
     * @param priceId Pyth price feed ID
     * @param tokenAddress Token address
     */
    function addPriceFeed(bytes32 priceId, address tokenAddress) 
        external 
        onlyOwner 
    {
        require(priceId != bytes32(0), "Invalid price ID");
        require(tokenAddress != address(0), "Invalid token");
        
        priceIdToToken[priceId] = tokenAddress;
        tokenToPriceId[tokenAddress] = priceId;
        
        emit PriceFeedAdded(priceId, tokenAddress);
    }
    
    /**
     * @dev Remove price feed
     * @param priceId Price feed ID
     */
    function removePriceFeed(bytes32 priceId) 
        external 
        onlyOwner 
    {
        address tokenAddress = priceIdToToken[priceId];
        delete priceIdToToken[priceId];
        delete tokenToPriceId[tokenAddress];
        delete latestPrices[priceId];
        delete priceHistory[priceId];
        
        emit PriceFeedRemoved(priceId);
    }
    
    /**
     * @dev Set CrashGuardCore address
     * @param _crashGuardCore CrashGuardCore contract
     */
    function setCrashGuardCore(address _crashGuardCore) 
        external 
        onlyOwner 
    {
        require(_crashGuardCore != address(0), "Invalid address");
        crashGuardCore = _crashGuardCore;
    }
    
    /**
     * @dev Emergency pause
     * @param paused Pause status
     */
    function setEmergencyPause(bool paused) 
        external 
        onlyOwner 
    {
        emergencyPaused = paused;
    }
    
    /**
     * @dev Get price by token address
     * @param tokenAddress Token address
     * @return PriceData Price data
     */
    function getPriceByToken(address tokenAddress) 
        external 
        view 
        returns (PriceData memory) 
    {
        bytes32 priceId = tokenToPriceId[tokenAddress];
        require(priceId != bytes32(0), "Token not monitored");
        return latestPrices[priceId];
    }
    
    /**
     * @dev Check if price is fresh
     * @param priceId Price feed ID
     * @return True if fresh
     */
    function isPriceFresh(bytes32 priceId) 
        external 
        view 
        returns (bool) 
    {
        PriceData memory priceData = latestPrices[priceId];
        return priceData.isValid && 
               (block.timestamp - priceData.timestamp) <= MAX_PRICE_AGE;
    }
    
    /**
     * @dev Check assets for crash
     * @param assets Token addresses
     * @param threshold Crash threshold (basis points)
     * @param timeWindow Time window
     * @return True if crash detected
     */
    function checkAssetsCrash(
        address[] calldata assets, 
        uint256 threshold, 
        uint256 timeWindow
    ) external view returns (bool) {
        require(assets.length > 0, "No assets");
        require(threshold > 0, "Invalid threshold");
        
        uint256 crashedCount = 0;
        
        for (uint256 i = 0; i < assets.length; i++) {
            bytes32 priceId = tokenToPriceId[assets[i]];
            if (priceId == bytes32(0)) continue;
            
            PriceData memory currentPrice = latestPrices[priceId];
            if (!currentPrice.isValid) continue;
            
            PriceData memory historicalPrice = _getHistoricalPrice(priceId, timeWindow);
            if (historicalPrice.timestamp == 0) continue;
            
            uint256 priceChange = _calculatePriceChange(historicalPrice.price, currentPrice.price);
            if (priceChange >= threshold) {
                crashedCount++;
            }
        }
        
        return crashedCount >= (assets.length * 6000) / 10000; // 60% threshold
    }
    
    // Internal functions
    
    function _storePriceData(bytes32 priceId, PythStructs.Price memory pythPrice) 
        private 
    {
        PriceData memory priceData = PriceData({
            price: _convertPythPrice(pythPrice.price, pythPrice.expo),
            timestamp: block.timestamp,
            confidence: _convertPythPrice(int64(pythPrice.conf), pythPrice.expo),
            isValid: pythPrice.price > 0
        });
        
        latestPrices[priceId] = priceData;
        
        PriceData[] storage history = priceHistory[priceId];
        if (history.length < HISTORY_LIMIT) {
            history.push(priceData);
        } else {
            uint256 oldestIndex = block.timestamp % HISTORY_LIMIT;
            history[oldestIndex] = priceData;
        }
    }
    
    function _convertPythPrice(int64 price, int32 expo) 
        private 
        pure 
        returns (uint256) 
    {
        if (price <= 0) return 0;
        
        uint256 absPrice = uint256(int256(price));
        
        if (expo >= 0) {
            return absPrice * (10 ** uint32(expo));
        } else {
            uint32 absExpo = uint32(uint256(int256(-expo)));
            if (absExpo >= 18) {
                return absPrice / (10 ** (absExpo - 8));
            } else {
                return absPrice * (10 ** (8 - absExpo));
            }
        }
    }
    
    function _getHistoricalPrice(bytes32 priceId, uint256 timeWindow) 
        private 
        view 
        returns (PriceData memory) 
    {
        PriceData[] storage history = priceHistory[priceId];
        uint256 targetTime = block.timestamp - timeWindow;
        
        for (uint256 i = history.length; i > 0; i--) {
            if (history[i - 1].timestamp <= targetTime) {
                return history[i - 1];
            }
        }
        
        return PriceData(0, 0, 0, false);
    }
    
    function _calculatePriceChange(uint256 oldPrice, uint256 newPrice) 
        private 
        pure 
        returns (uint256) 
    {
        if (oldPrice == 0) return 0;
        if (newPrice >= oldPrice) return 0;
        
        uint256 decrease = oldPrice - newPrice;
        return (decrease * 10000) / oldPrice;
    }
    
    function _getMonitoredPriceIds() 
        private 
        view 
        returns (bytes32[] memory) 
    {
        // In production, maintain a registry of monitored price IDs
        bytes32[] memory priceIds = new bytes32[](0);
        return priceIds;
    }
}
