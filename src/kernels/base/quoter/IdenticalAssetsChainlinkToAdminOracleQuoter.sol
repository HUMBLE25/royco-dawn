// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IdenticalAssetsAdminOracleQuoter } from "./base/IdenticalAssetsAdminOracleQuoter.sol";
import { IdenticalAssetsChainlinkOracleQuoter } from "./base/IdenticalAssetsChainlinkOracleQuoter.sol";
import { IdenticalAssetsOracleQuoter } from "./base/IdenticalAssetsOracleQuoter.sol";

/**
 * @title IdenticalAssetsChainlinkToAdminOracleQuoter
 * @notice Quoter to convert tranche units to/from NAV units using a Chainlink (compatible) oracle to convert tranche units to reference assets which uses an admin controlled oracle to convert to NAV units
 * @dev Use case: Convert PT-USDe (Tranche unit) to USDe (Reference asset) using a Pendle oracle and convert USDe to USD (NAV unit) using an admin set rate
 */
abstract contract IdenticalAssetsChainlinkToAdminOracleQuoter is IdenticalAssetsChainlinkOracleQuoter, IdenticalAssetsAdminOracleQuoter {
    /**
     * @notice Initializes the identical assets chainlink oracle quoter and the base identical assets oracle quoter
     * @param _initialConversionRateRAY The initial conversion rate as defined by the oracle, scaled to RAY precision
     * @param _trancheAssetToReferenceAssetOracle The tranche asset to reference asset oracle
     * @param _stalenessThresholdSeconds The staleness threshold in seconds
     */
    function __IdenticalAssetsChainlinkToAdminOracleQuoter_init(
        uint256 _initialConversionRateRAY,
        address _trancheAssetToReferenceAssetOracle,
        uint48 _stalenessThresholdSeconds
    )
        internal
        onlyInitializing
    {
        __IdenticalAssetsAdminOracleQuoter_init(_initialConversionRateRAY);
        __IdenticalAssetsChainlinkOracleQuoter_init_unchained(_trancheAssetToReferenceAssetOracle, _stalenessThresholdSeconds);
    }

    /// @inheritdoc IdenticalAssetsAdminOracleQuoter
    function setConversionRate(uint256 _conversionRateRAY) public override(IdenticalAssetsOracleQuoter, IdenticalAssetsAdminOracleQuoter) restricted {
        IdenticalAssetsAdminOracleQuoter.setConversionRate(_conversionRateRAY);
    }

    /// @inheritdoc IdenticalAssetsChainlinkOracleQuoter
    function getTrancheUnitToNAVUnitConversionRate()
        public
        view
        override(IdenticalAssetsOracleQuoter, IdenticalAssetsChainlinkOracleQuoter)
        returns (uint256 trancheToNAVUnitConversionRateRAY)
    {
        return IdenticalAssetsChainlinkOracleQuoter.getTrancheUnitToNAVUnitConversionRate();
    }
}
