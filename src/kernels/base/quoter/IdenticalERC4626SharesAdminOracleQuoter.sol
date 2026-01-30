// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IdenticalAssetsAdminOracleQuoter } from "./base/IdenticalAssetsAdminOracleQuoter.sol";
import { IdenticalAssetsOracleQuoter } from "./base/IdenticalAssetsOracleQuoter.sol";
import { IdenticalERC4626SharesOracleQuoter } from "./base/IdenticalERC4626SharesOracleQuoter.sol";

/**
 * @title IdenticalERC4626SharesAdminOracleQuoter
 * @dev Mandates that the base asset to NAV units uses an admin controlled oracle
 * @dev The senior and junior tranches must have the same ERC4626 vault share as its tranche unit
 * @dev Use case: Convert sUSDe (Tranche unit) to USDe (base assets) using ERC4626's convertToAssets and convert USDe to USD (NAV unit) using an admin set rate
 */
abstract contract IdenticalERC4626SharesAdminOracleQuoter is IdenticalERC4626SharesOracleQuoter, IdenticalAssetsAdminOracleQuoter {
    /**
     * @notice Initializes the identical assets chainlink oracle quoter and the base identical assets oracle quoter
     * @param _initialConversionRateRAY The initial conversion rate as defined by the oracle, scaled to RAY precision
     */
    function __IdenticalERC4626SharesAdminOracleQuoter_init(uint256 _initialConversionRateRAY) internal onlyInitializing {
        __IdenticalAssetsAdminOracleQuoter_init(_initialConversionRateRAY);
    }

    /// @inheritdoc IdenticalAssetsAdminOracleQuoter
    function setConversionRate(uint256 _conversionRateRAY) public override(IdenticalAssetsOracleQuoter, IdenticalAssetsAdminOracleQuoter) restricted {
        IdenticalAssetsAdminOracleQuoter.setConversionRate(_conversionRateRAY);
    }

    /// @inheritdoc IdenticalERC4626SharesOracleQuoter
    function getTrancheUnitToNAVUnitConversionRateRAY()
        public
        view
        override(IdenticalAssetsOracleQuoter, IdenticalERC4626SharesOracleQuoter)
        returns (uint256 trancheToNAVUnitConversionRateRAY)
    {
        return IdenticalERC4626SharesOracleQuoter.getTrancheUnitToNAVUnitConversionRateRAY();
    }
}
