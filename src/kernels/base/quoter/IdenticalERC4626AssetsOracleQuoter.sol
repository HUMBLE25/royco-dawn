// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { RAY } from "../../../libraries/Constants.sol";
import { IdenticalAssetsOracleQuoter } from "./base/IdenticalAssetsOracleQuoter.sol";

/**
 * @title IdenticalERC4626AssetsOracleQuoter
 * @notice Quoter for markets where both tranches use the same ERC4626 compliant tranche asset and the NAV is represented in the tranche's share's value in some reference asset
 * @dev Example: Tranche Unit: sNUSD, NAV Unit: USD where x Tranche Unit = x * sNUSD share price in NUSD * NUSD share price in USD
 */
abstract contract IdenticalERC4626AssetsOracleQuoter is IdenticalAssetsOracleQuoter {
    using Math for uint256;

    /**
     * @notice Returns the conversion rate from tranche units to NAV units, scaled to RAY precision
     * @dev This function assumes that the tranche token is an ERC4626 compliant vault
     * @dev The conversion rate is calculated as value_of_vault_share_in_vault_asset * value_of_vault_asset_in_NAV_units, scaled to RAY precision
     * @return trancheToNAVUnitConversionRateRAY The conversion rate from tranche token units to NAV units, scaled to RAY precision
     */
    function getTrancheUnitToNAVUnitConversionRate() public view override returns (uint256 trancheToNAVUnitConversionRateRAY) {
        // Fetch the conversion rate from the vault asset (ERC4626) to it's underlying asset, scaled to RAY precision
        uint256 trancheUnitToVaultAssetsConversionRateRAY = IERC4626(ST_ASSET).convertToAssets(RAY);

        // Resolve the vaultAsset to NAV unit conversion rate
        uint256 vaultAssetToNAVUnitConversionRateRAY = getStoredConversionRateRAY();
        if (vaultAssetToNAVUnitConversionRateRAY != SENTINEL_TRANCHE_TO_NAV_UNIT_CONVERSION_RATE) {
            // If the stored conversion rate is the sentinel value, query the oracle for the rate
            // This is expected to return a RAY precision value
            vaultAssetToNAVUnitConversionRateRAY = _getConversionRateFromOracle();
        }

        // Calculate the conversion rate from tranche token units to NAV units, scaled to RAY precision
        trancheToNAVUnitConversionRateRAY = trancheUnitToVaultAssetsConversionRateRAY.mulDiv(vaultAssetToNAVUnitConversionRateRAY, RAY, Math.Rounding.Floor);
    }
}
