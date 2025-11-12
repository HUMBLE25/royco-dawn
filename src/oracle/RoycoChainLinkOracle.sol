// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20Metadata } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";
import { IRoycoOracle } from "../interfaces/IRoycoOracle.sol";

/**
 * @title RoycoChainLinkOracle
 * @notice Oracle that quotes the price of a one whole collateral asset in terms of whole commitment assets
 */
contract RoycoChainLinkOracle is IRoycoOracle {
    using Math for uint256;

    /// @notice Chainlink price feed for the collateral asset
    /// @dev Returns the price of 1 whole collateral token in the same base currency as the commitment asset price feed
    AggregatorV3Interface public immutable COLLATERAL_ASSET_PRICE_FEED;

    /// @notice Chainlink price feed for the commitment asset
    /// @dev Returns the price of 1 whole commitment token in the same base currency as the collateral asset price feed
    AggregatorV3Interface public immutable COMMITMENT_ASSET_PRICE_FEED;

    /// @notice Scaling factor used to normalize the price ratio.
    uint256 public immutable SCALE_FACTOR;

    /**
     * @notice Deploys the oracle using ERC20 metadata and Chainlink feeds for both assets
     * @dev The collateral and commitment price feeds must share the same base currency (eg. USD)
     * @param _collateralAsset Address of the ERC20 collateral asset
     * @param _collateralAssetPriceFeed Address of the chainlink price feed for the collateral asset
     * @param _commitmentAsset Address of the ERC20 commitment asset
     * @param _commitmentAssetPriceFeed Address of the chainlink price feed for the commitment asset
     */
    constructor(address _collateralAsset, address _collateralAssetPriceFeed, address _commitmentAsset, address _commitmentAssetPriceFeed) {
        COLLATERAL_ASSET_PRICE_FEED = AggregatorV3Interface(_collateralAssetPriceFeed);
        COMMITMENT_ASSET_PRICE_FEED = AggregatorV3Interface(_commitmentAssetPriceFeed);

        SCALE_FACTOR = 10
            ** (
                27 // Base scale factor for RAY
                    + IERC20Metadata(_commitmentAsset).decimals() + COMMITMENT_ASSET_PRICE_FEED.decimals() // Scaled to express price as whole commitment assets per whole collateral asset
                    - IERC20Metadata(_collateralAsset).decimals() - COLLATERAL_ASSET_PRICE_FEED.decimals()
            );
    }

    /// @inheritdoc IRoycoOracle
    function getPrice() external view returns (uint256) {
        return SCALE_FACTOR.mulDiv(_getPrice(COLLATERAL_ASSET_PRICE_FEED), _getPrice(COMMITMENT_ASSET_PRICE_FEED));
    }

    /**
     * @notice Fetches the latest raw answer from a Chainlink price feed.
     * @dev Doesn't check for price staleness
     * @param _priceFeed Chainlink aggregator to query.
     * @return price Latest raw answer from the feed.
     */
    function _getPrice(AggregatorV3Interface _priceFeed) internal view returns (uint256 price) {
        (, int256 answer,,,) = _priceFeed.latestRoundData();
        return uint256(answer);
    }
}
