// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { Math } from "../../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { RAY } from "../../../../libraries/Constants.sol";
import { IdenticalAssetsOracleQuoter } from "./IdenticalAssetsOracleQuoter.sol";

/**
 * @title IdenticalERC4626SharesOracleQuoter
 * @notice Quoter to convert tranche units (ERC4626 vault shares) to/from NAV units by converting the shares to base assets and converting base assets to NAV units using an admin or oracle set rate
 * @dev The senior and junior tranches must have the same ERC4626 vault share as its tranche unit
 * @dev Use case: Convert sUSDE (Tranche unit) to USDE (base assets) using ERC4626's convertToAssets and convert USDE to USD (NAV unit) using an admin or oracle set rate
 */
abstract contract IdenticalERC4626SharesOracleQuoter is IdenticalAssetsOracleQuoter {
    using Math for uint256;

    /**
     * @notice Returns the conversion rate from tranche units to NAV units, scaled to RAY precision
     * @dev This function assumes that the tranche token is an ERC4626 compliant vault
     * @dev The conversion rate is calculated as value_of_vault_share_in_vault_asset * value_of_vault_asset_in_NAV_units, scaled to RAY precision
     * @return trancheToNAVUnitConversionRateRAY The conversion rate from tranche token units to NAV units, scaled to RAY precision
     */
    function getTrancheUnitToNAVUnitConversionRate()
        public
        view
        virtual
        override(IdenticalAssetsOracleQuoter)
        returns (uint256 trancheToNAVUnitConversionRateRAY)
    {
        // Fetch the conversion rate from the vault asset (ERC4626) to it's underlying asset, scaled to RAY precision
        uint256 trancheUnitToVaultAssetsConversionRateRAY = IERC4626(ST_ASSET).convertToAssets(RAY);

        // Resolve the vaultAsset to NAV unit conversion rate
        uint256 vaultAssetToNAVUnitConversionRateRAY = getStoredConversionRateRAY();
        if (vaultAssetToNAVUnitConversionRateRAY == SENTINEL_CONVERSION_RATE) {
            // If the stored conversion rate is the sentinel value, query the oracle for the rate
            // This is expected to return a RAY precision value
            vaultAssetToNAVUnitConversionRateRAY = _getConversionRateFromOracle();
        }

        // Calculate the conversion rate from tranche token units to NAV units, scaled to RAY precision
        trancheToNAVUnitConversionRateRAY = trancheUnitToVaultAssetsConversionRateRAY.mulDiv(vaultAssetToNAVUnitConversionRateRAY, RAY, Math.Rounding.Floor);
    }
}
