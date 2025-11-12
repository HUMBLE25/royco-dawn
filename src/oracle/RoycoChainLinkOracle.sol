// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20Metadata } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { IRoycoOracle } from "../interfaces/IRoycoOracle.sol";

/**
 * @title RoycoChainLinkOracle
 * @notice Royco's chainlink oracle price feed
 * @dev Responsible for returning the price of collateral asset in terms commitment assets
 */
contract RoycoChainLinkOracle is IRoycoOracle {
    using Math for uint256;

    AggregatorV3Interface public immutable COLLATERAL_ASSET_PRICE_FEED;
    AggregatorV3Interface public immutable COMMITMENT_ASSET_PRICE_FEED;
    uint256 public immutable SCALE_FACTOR;

    constructor(address _collateralAsset, address _collateralAssetPriceFeed, address _commitmentAsset, address _commitmentAssetPriceFeed) {
        COLLATERAL_ASSET_PRICE_FEED = AggregatorV3Interface(_collateralAssetPriceFeed);
        COMMITMENT_ASSET_PRICE_FEED = AggregatorV3Interface(_commitmentAssetPriceFeed);

        SCALE_FACTOR = 10
            ** (
                27 // Base scaling factor for RAY
                    + IERC20Metadata(_commitmentAsset).decimals() + COMMITMENT_ASSET_PRICE_FEED.decimals() // Commitment asset precision / Collateral asset precision
                    - IERC20Metadata(_collateralAsset).decimals() - COLLATERAL_ASSET_PRICE_FEED.decimals()
            );
    }

    function getPrice() external view returns (uint256) {
        return SCALE_FACTOR.mulDiv(_getPrice(COLLATERAL_ASSET_PRICE_FEED), _getPrice(COMMITMENT_ASSET_PRICE_FEED));
    }

    function _getPrice(AggregatorV3Interface _priceFeed) internal view returns (uint256) {
        (, int256 priceInBaseAsset,,,) = _priceFeed.latestRoundData();
        return uint256(priceInBaseAsset);
    }
}
