// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IRoycoOracle} from "../interfaces/IRoycoOracle.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

contract RoycoCLOracle is IRoycoOracle {
    AggregatorV3Interface immutable ASSET_USD_PRICE_FEED;

    constructor(address _assetUsdPriceFeed) {
        ASSET_USD_PRICE_FEED = AggregatorV3Interface(_assetUsdPriceFeed);
    }

    function getAssetPriceUSD() external view returns (uint256) {
        (, int256 priceInUSD,,,) = ASSET_USD_PRICE_FEED.latestRoundData();
        return uint256(priceInUSD);
    }
}
