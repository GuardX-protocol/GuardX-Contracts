// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPythPriceMonitor {
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
        bool isValid;
    }

    struct CrashThresholds {
        uint256 singleAssetThreshold;
        uint256 multiAssetThreshold;
        uint256 timeWindow;
        uint256 minimumAssets;
    }

    event PricesUpdated(bytes32[] priceIds, uint256 timestamp);
    event CrashDetected(address[] assets, uint256 timestamp, uint256 severity);

    function updatePrices(bytes32[] calldata priceIds) external payable;
    function getLatestPrice(bytes32 priceId) external view returns (PriceData memory);
    function detectMultiAssetCrash(CrashThresholds memory thresholds) external view returns (bool);
    function getPriceHistory(bytes32 priceId, uint256 timeRange) external view returns (PriceData[] memory);
}