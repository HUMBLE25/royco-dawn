// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { AggregatorV3Interface } from "../../../interfaces/external/chainlink/AggregatorV3Interface.sol";
import { RAY } from "../../../libraries/Constants.sol";
import { IdenticalAssetsOracleQuoter } from "./base/IdenticalAssetsOracleQuoter.sol";

/**
 * @title IdenticalAssetsChainlinkOracleQuoter
 * @notice Quoter for markets where both tranches use the same tranche asset
 * @dev The NAV Unit is calculated as Tranche Unit * Chainlink Oracle Price * Conversion Rate (from storage or another oracle)
 * @dev For Example: Tranche Unit: PT-cUSD, NAV Unit: USDC where x Tranche Unit = x * PT-cUSD price in SY-cUSD * SY-cUSD price in USDC
 */
abstract contract IdenticalAssetsChainlinkOracleQuoter is IdenticalAssetsOracleQuoter {
    using Math for uint256;

    /// @notice Thrown when the tranche asset to reference asset oracle is the zero address
    error INVALID_TRANCHE_ASSET_TO_REFERENCE_ASSET_ORACLE();

    /// @notice Thrown when the staleness threshold seconds is zero
    error INVALID_STALENESS_THRESHOLD_SECONDS();

    /// @notice Thrown when the price is stale
    error PRICE_STALE();

    /// @notice Thrown when the price is invalid
    error PRICE_INVALID();

    /// @notice Thrown when the price is incomplete
    error PRICE_INCOMPLETE();

    /// @notice Emitted when the identical assets chainlink oracle quoter is updated
    event IdenticalAssetsChainlinkOracleUpdated(
        address indexed _trancheAssetToReferenceAssetOracle,
        uint8 indexed _trancheAssetToReferenceAssetOracleDecimalPrecision,
        uint48 indexed _stalenessThresholdSeconds
    );

    // keccak256(abi.encode(uint256(keccak256("Royco.storage.IdenticalAssetsChainlinkOracleQuoterState")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant IDENTICAL_ASSETS_CHAINLINK_ORACLE_QUOTER_STORAGE_SLOT = 0x36321e8ea9ef16a1b272d9cece1e9b80ed6532a47572ae703d9c65a3a5fa1800;

    /// @dev Storage state for the Royco identical assets chainlink oracle quoter
    /// @custom:storage-location erc7201:Royco.storage.IdenticalAssetsChainlinkOracleQuoterState
    struct IdenticalAssetsChainlinkOracleQuoterState {
        address trancheAssetToReferenceAssetOracle;
        uint8 trancheAssetToReferenceAssetOracleDecimalPrecision;
        uint48 stalenessThresholdSeconds;
    }

    /**
     * @notice Initializes the identical assets chainlink oracle quoter
     * @param _trancheAssetToReferenceAssetOracle The tranche asset to reference asset oracle
     * @param _stalenessThresholdSeconds The staleness threshold seconds
     */
    function __IdenticalAssetsChainlinkOracleQuoter_init(
        address _trancheAssetToReferenceAssetOracle,
        uint48 _stalenessThresholdSeconds
    )
        internal
        onlyInitializing
    {
        _setTrancheAssetToReferenceAssetOracle(_trancheAssetToReferenceAssetOracle, _stalenessThresholdSeconds);
    }

    /**
     * @notice Returns the conversion rate from tranche units to NAV units, scaled to RAY precision
     * @dev The conversion rate is calculated as Tranche Asset Price in Reference Asset * Reference Asset Price in NAV Units
     *      NAV Units = Tranche Asset Price in Reference Asset * Reference Asset Price in NAV Units
     * @return trancheToNAVUnitConversionRateRAY The conversion rate from tranche token units to NAV units, scaled to RAY precision
     */
    function getTrancheUnitToNAVUnitConversionRate() public view override returns (uint256 trancheToNAVUnitConversionRateRAY) {
        // Fetch the Tranche Asset to the reference asset
        (uint256 trancheAssetPriceInReferenceAsset, uint256 precision) = _queryChainlinkOracle();

        // Resolve the Reference Asset to NAV unit conversion rate
        uint256 referenceAssetToNAVUnitConversionRateRAY = getStoredConversionRateRAY();
        if (referenceAssetToNAVUnitConversionRateRAY == SENTINEL_CONVERSION_RATE) {
            // If the stored conversion rate is the sentinel value, query the oracle for the rate
            // This is expected to return a RAY precision value
            referenceAssetToNAVUnitConversionRateRAY = _getConversionRateFromOracle();
        }

        // Calculate the conversion rate from tranche token units to NAV units, scaled to RAY precision
        trancheToNAVUnitConversionRateRAY =
            trancheAssetPriceInReferenceAsset.mulDiv(referenceAssetToNAVUnitConversionRateRAY, precision * RAY, Math.Rounding.Floor);
    }

    /**
     * @notice Sets the tranche asset to reference asset oracle
     * @param _trancheAssetToReferenceAssetOracle The new tranche asset to reference asset oracle
     * @param _stalenessThresholdSeconds The new staleness threshold seconds
     */
    function setTrancheAssetToReferenceAssetOracle(address _trancheAssetToReferenceAssetOracle, uint48 _stalenessThresholdSeconds) external restricted {
        _setTrancheAssetToReferenceAssetOracle(_trancheAssetToReferenceAssetOracle, _stalenessThresholdSeconds);
    }

    /**
     * @notice Queries the chainlink oracle for the price
     * @dev The price is returned as the answer from the latest round
     * @return price The price from the latest round
     * @return precision The precision of the price
     */
    function _queryChainlinkOracle() internal view returns (uint256 price, uint256 precision) {
        IdenticalAssetsChainlinkOracleQuoterState storage $ = _getIdenticalAssetsChainlinkOracleQuoterStorage();

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface($.trancheAssetToReferenceAssetOracle).latestRoundData();

        require(updatedAt >= block.timestamp - $.stalenessThresholdSeconds, PRICE_STALE());
        require(answer > 0, PRICE_INVALID());
        require(answeredInRound >= roundId, PRICE_INCOMPLETE());

        // forge-lint: disable-next-item(unsafe-typecast)
        price = uint256(answer);
        precision = 10 ** uint256($.trancheAssetToReferenceAssetOracleDecimalPrecision);
    }

    /**
     * @notice Sets the tranche asset to reference asset oracle
     * @param _trancheAssetToReferenceAssetOracle The new tranche asset to reference asset oracle
     * @param _stalenessThresholdSeconds The new staleness threshold seconds
     */
    function _setTrancheAssetToReferenceAssetOracle(address _trancheAssetToReferenceAssetOracle, uint48 _stalenessThresholdSeconds) internal {
        require(_trancheAssetToReferenceAssetOracle != address(0), INVALID_TRANCHE_ASSET_TO_REFERENCE_ASSET_ORACLE());
        require(_stalenessThresholdSeconds > 0, INVALID_STALENESS_THRESHOLD_SECONDS());

        IdenticalAssetsChainlinkOracleQuoterState storage $ = _getIdenticalAssetsChainlinkOracleQuoterStorage();

        $.trancheAssetToReferenceAssetOracle = _trancheAssetToReferenceAssetOracle;
        $.trancheAssetToReferenceAssetOracleDecimalPrecision = AggregatorV3Interface(_trancheAssetToReferenceAssetOracle).decimals();
        $.stalenessThresholdSeconds = _stalenessThresholdSeconds;
    }

    /**
     * @notice Returns a storage pointer to the IdenticalAssetsChainlinkOracleQuoterState storage
     * @dev Uses ERC-7201 storage slot pattern for collision-resistant storage
     * @return $ Storage pointer
     */
    function _getIdenticalAssetsChainlinkOracleQuoterStorage() private pure returns (IdenticalAssetsChainlinkOracleQuoterState storage $) {
        assembly ("memory-safe") {
            $.slot := IDENTICAL_ASSETS_CHAINLINK_ORACLE_QUOTER_STORAGE_SLOT
        }
    }
}
