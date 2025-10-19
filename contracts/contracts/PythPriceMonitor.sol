// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IPythPriceMonitor.sol";

contract PythPriceMonitor is IPythPriceMonitor, Ownable, ReentrancyGuard {
    IPyth public immutable PYTH;
    
    // Price data storage
    mapping(bytes32 => PriceData) private latestPrices;
    mapping(bytes32 => PriceData[]) private priceHistory;
    mapping(bytes32 => address) public priceIdToToken;
    mapping(address => bytes32) public tokenToPriceId;
    
    // Crash detection parameters
    uint256 private constant MAX_PRICE_AGE = 300; // 5 minutes
    uint256 private constant HISTORY_LIMIT = 100; // Keep last 100 price updates
    uint256 private constant PRECISION = 1e8; // Price precision
    
    // Emergency controls
    bool public emergencyPaused = false;
    address public crashGuardCore;
    
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
     * @dev Update prices from Pyth Network
     * @param priceIds Array of price feed IDs to update
     */
    function updatePrices(bytes32[] calldata priceIds) 
        external 
        payable 
        nonReentrant 
        notPaused 
    {
        require(priceIds.length > 0, "No price IDs provided");
        
        // Get update fee from Pyth
        bytes[] memory emptyUpdateData = new bytes[](priceIds.length);
        uint256 updateFee = PYTH.getUpdateFee(emptyUpdateData);
        require(msg.value >= updateFee, "Insufficient fee");
        
        // Get prices from Pyth contract
        for (uint256 i = 0; i < priceIds.length; i++) {
            try PYTH.getPrice(priceIds[i]) returns (PythStructs.Price memory price) {
                _storePriceData(priceIds[i], price);
            } catch {
                // Handle individual price feed failures gracefully
                continue;
            }
        }
        
        // Refund excess payment
        if (msg.value > updateFee) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - updateFee}("");
            require(success, "Refund failed");
        }
        
        emit PricesUpdated(priceIds, block.timestamp);
    }
    
    /**
     * @dev Get latest price for a given price ID
     * @param priceId Pyth price feed ID
     * @return PriceData struct with latest price information
     */
    function getLatestPrice(bytes32 priceId) 
        external 
        view 
        returns (PriceData memory) 
    {
        PriceData memory priceData = latestPrices[priceId];
        require(priceData.timestamp > 0, "Price not available");
        
        // Check if price is stale
        if (block.timestamp - priceData.timestamp > MAX_PRICE_AGE) {
            priceData.isValid = false;
        }
        
        return priceData;
    }
    
    /**
     * @dev Detect multi-asset crash based on thresholds
     * @param thresholds Crash detection parameters
     * @return True if crash conditions are met
     */
    function detectMultiAssetCrash(CrashThresholds memory thresholds) 
        external 
        view 
        returns (bool) 
    {
        require(thresholds.singleAssetThreshold > 0, "Invalid single asset threshold");
        require(thresholds.multiAssetThreshold > 0, "Invalid multi asset threshold");
        require(thresholds.timeWindow > 0, "Invalid time window");
        require(thresholds.minimumAssets >= 2, "Minimum assets must be >= 2");
        
        uint256 crashedAssets = 0;
        uint256 totalAssets = 0;
        
        // Check all monitored assets for crash conditions
        // This is a simplified implementation - in practice, you'd iterate through
        // a registry of monitored assets
        bytes32[] memory monitoredPriceIds = _getMonitoredPriceIds();
        
        for (uint256 i = 0; i < monitoredPriceIds.length; i++) {
            bytes32 priceId = monitoredPriceIds[i];
            PriceData memory currentPrice = latestPrices[priceId];
            
            if (!currentPrice.isValid || 
                block.timestamp - currentPrice.timestamp > MAX_PRICE_AGE) {
                continue;
            }
            
            totalAssets++;
            
            // Get historical price for comparison
            PriceData memory historicalPrice = _getHistoricalPrice(priceId, thresholds.timeWindow);
            
            if (historicalPrice.timestamp > 0) {
                uint256 priceChange = _calculatePriceChange(historicalPrice.price, currentPrice.price);
                
                if (priceChange >= thresholds.singleAssetThreshold) {
                    crashedAssets++;
                }
            }
        }
        
        // Check if crash conditions are met
        if (totalAssets >= thresholds.minimumAssets && crashedAssets >= thresholds.minimumAssets) {
            uint256 crashPercentage = (crashedAssets * 10000) / totalAssets; // Basis points
            return crashPercentage >= thresholds.multiAssetThreshold;
        }
        
        return false;
    }
    
    /**
     * @dev Get price history for a given price ID
     * @param priceId Pyth price feed ID
     * @param timeRange Time range in seconds
     * @return Array of historical price data
     */
    function getPriceHistory(bytes32 priceId, uint256 timeRange) 
        external 
        view 
        returns (PriceData[] memory) 
    {
        require(timeRange > 0, "Invalid time range");
        
        PriceData[] storage history = priceHistory[priceId];
        uint256 cutoffTime = block.timestamp - timeRange;
        
        // Count valid entries within time range
        uint256 validCount = 0;
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].timestamp >= cutoffTime) {
                validCount++;
            }
        }
        
        // Create result array
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
     * @dev Add a new price feed to monitor
     * @param priceId Pyth price feed ID
     * @param tokenAddress Associated token address
     */
    function addPriceFeed(bytes32 priceId, address tokenAddress) 
        external 
        onlyOwner 
    {
        require(priceId != bytes32(0), "Invalid price ID");
        require(tokenAddress != address(0), "Invalid token address");
        
        priceIdToToken[priceId] = tokenAddress;
        tokenToPriceId[tokenAddress] = priceId;
    }
    
    /**
     * @dev Remove a price feed from monitoring
     * @param priceId Pyth price feed ID
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
    }
    
    /**
     * @dev Set CrashGuardCore contract address
     * @param _crashGuardCore Address of the CrashGuardCore contract
     */
    function setCrashGuardCore(address _crashGuardCore) 
        external 
        onlyOwner 
    {
        require(_crashGuardCore != address(0), "Invalid address");
        crashGuardCore = _crashGuardCore;
    }
    
    /**
     * @dev Emergency pause function
     * @param paused True to pause, false to unpause
     */
    function setEmergencyPause(bool paused) 
        external 
        onlyOwner 
    {
        emergencyPaused = paused;
    }
    
    /**
     * @dev Get price for token address
     * @param tokenAddress Token contract address
     * @return PriceData struct
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
     * @dev Check if crash conditions exist for specific assets
     * @param assets Array of token addresses to check
     * @param threshold Crash threshold percentage (basis points)
     * @param timeWindow Time window for comparison
     * @return True if crash detected
     */
    function checkAssetsCrash(
        address[] calldata assets, 
        uint256 threshold, 
        uint256 timeWindow
    ) external view returns (bool) {
        require(assets.length > 0, "No assets provided");
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
        
        return crashedCount >= (assets.length * 6000) / 10000; // 60% of assets crashed
    }
    
    /**
     * @dev Internal function to store price data
     * @param priceId Price feed ID
     * @param pythPrice Pyth price struct
     */
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
        
        // Add to history
        PriceData[] storage history = priceHistory[priceId];
        history.push(priceData);
        
        // Maintain history limit
        if (history.length > HISTORY_LIMIT) {
            // Remove oldest entry
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history.pop();
        }
    }
    
    /**
     * @dev Convert Pyth price format to standard format
     * @param price Pyth price value
     * @param expo Pyth price exponent
     * @return Converted price
     */
    function _convertPythPrice(int64 price, int32 expo) 
        private 
        pure 
        returns (uint256) 
    {
        if (price <= 0) return 0;
        
        uint256 absPrice;
        if (price >= 0) {
            absPrice = uint256(int256(price));
        } else {
            absPrice = uint256(int256(-price));
        }
        
        if (expo >= 0) {
            return absPrice * (10 ** uint32(expo));
        } else {
            uint32 absExpo = uint32(uint256(int256(-expo)));
            if (absExpo >= 18) {
                return absPrice / (10 ** (absExpo - 8)); // Maintain 8 decimal precision
            } else {
                return absPrice * (10 ** (8 - absExpo));
            }
        }
    }
    
    /**
     * @dev Get historical price within time window
     * @param priceId Price feed ID
     * @param timeWindow Time window in seconds
     * @return Historical price data
     */
    function _getHistoricalPrice(bytes32 priceId, uint256 timeWindow) 
        private 
        view 
        returns (PriceData memory) 
    {
        PriceData[] storage history = priceHistory[priceId];
        uint256 targetTime = block.timestamp - timeWindow;
        
        // Find closest historical price
        for (uint256 i = history.length; i > 0; i--) {
            if (history[i - 1].timestamp <= targetTime) {
                return history[i - 1];
            }
        }
        
        return PriceData(0, 0, 0, false);
    }
    
    /**
     * @dev Calculate price change percentage
     * @param oldPrice Previous price
     * @param newPrice Current price
     * @return Price change in basis points
     */
    function _calculatePriceChange(uint256 oldPrice, uint256 newPrice) 
        private 
        pure 
        returns (uint256) 
    {
        if (oldPrice == 0) return 0;
        
        if (newPrice >= oldPrice) {
            return 0; // No crash if price increased
        }
        
        uint256 decrease = oldPrice - newPrice;
        return (decrease * 10000) / oldPrice; // Return in basis points
    }
    
    /**
     * @dev Get list of monitored price IDs
     * @return Array of price IDs being monitored
     */
    function _getMonitoredPriceIds() 
        private 
        view 
        returns (bytes32[] memory) 
    {
        // This is a simplified implementation
        // In practice, you'd maintain a registry of monitored price IDs
        bytes32[] memory priceIds = new bytes32[](0);
        return priceIds;
    }
    
    /**
     * @dev Get update fee for price updates
     * @param priceIds Array of price feed IDs
     * @return Required fee amount
     */
    function getUpdateFee(bytes32[] calldata priceIds) 
        external 
        view 
        returns (uint256) 
    {
        bytes[] memory emptyUpdateData = new bytes[](priceIds.length);
        return PYTH.getUpdateFee(emptyUpdateData);
    }
    
    /**
     * @dev Check if price data is fresh
     * @param priceId Price feed ID
     * @return True if price is fresh
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
}