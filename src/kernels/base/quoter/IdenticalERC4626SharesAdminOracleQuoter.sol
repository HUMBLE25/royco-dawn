// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IdenticalAssetsAdminOracleQuoter } from "./base/IdenticalAssetsAdminOracleQuoter.sol";
import { IdenticalAssetsOracleQuoter } from "./base/IdenticalAssetsOracleQuoter.sol";
import { IdenticalERC4626SharesOracleQuoter } from "./base/IdenticalERC4626SharesOracleQuoter.sol";

/**
 * @title IdenticalERC4626SharesAdminOracleQuoter
 * @notice Quoter to convert tranche units (ERC4626 vault shares) to/from NAV units by converting the shares to base assets and converting base assets to NAV units using an admin controlled oracle
 * @dev The senior and junior tranches must have the same ERC4626 vault share as its tranche unit
 * @dev Use case: Convert sUSDE (Tranche unit) to USDE (base assets) using ERC4626's convertToAssets and convert USDE to USD (NAV unit) using an admin set rate
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
    function getTrancheUnitToNAVUnitConversionRate()
        public
        view
        override(IdenticalAssetsOracleQuoter, IdenticalERC4626SharesOracleQuoter)
        returns (uint256 trancheToNAVUnitConversionRateRAY)
    {
        return IdenticalERC4626SharesOracleQuoter.getTrancheUnitToNAVUnitConversionRate();
    }
}
