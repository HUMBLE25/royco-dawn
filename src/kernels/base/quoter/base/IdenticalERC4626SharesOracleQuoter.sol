// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC20Metadata, IERC4626 } from "../../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { Math } from "../../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { RAY, RAY_DECIMALS } from "../../../../libraries/Constants.sol";
import { IdenticalAssetsOracleQuoter } from "./IdenticalAssetsOracleQuoter.sol";

/**
 * @title IdenticalERC4626SharesOracleQuoter
 * @notice Quoter to convert tranche units (ERC4626 vault shares) to/from NAV units by converting the shares to base assets and converting base assets to NAV units using an admin or oracle set rate
 * @dev The senior and junior tranches must have the same ERC4626 vault share as its tranche unit
 * @dev Use case: Convert sUSDE (Tranche unit) to USDE (base assets) using ERC4626's convertToAssets and convert USDE to USD (NAV unit) using an admin or oracle set rate
 */
abstract contract IdenticalERC4626SharesOracleQuoter is IdenticalAssetsOracleQuoter {
    using Math for uint256;

    /// @dev The share amount to pass to convertToAssets() such that the result is scaled to RAY precision
    uint256 internal immutable SHARES_TO_CONVERT_TO_ASSETS;

    constructor() {
        // NOTE: Both tranche assets are identical ERC4626 shares
        // Compute the share amount to pass to convertToAssets() such that the result is scaled to RAY precision
        // OUTPUT_DECIMALS = INPUT_DECIMALS + BASE_ASSET_DECIMALS - TRANCHE_DECIMALS
        // For OUTPUT_DECIMALS to have RAY_DECIMALS of precision:
        // INPUT_DECIMALS = RAY_DECIMALS + TRANCHE_DECIMALS - BASE_ASSET_DECIMALS
        // OUTPUT_DECIMALS = (RAY_DECIMALS + TRANCHE_DECIMALS - BASE_ASSET_DECIMALS) + BASE_ASSET_DECIMALS - TRANCHE_DECIMALS
        // OUTPUT_DECIMALS = RAY_DECIMALS
        SHARES_TO_CONVERT_TO_ASSETS = 10 ** (RAY_DECIMALS + IERC4626(ST_ASSET).decimals() - IERC20Metadata(IERC4626(ST_ASSET).asset()).decimals());
    }

    /**
     * @notice Returns the conversion rate from tranche units to NAV units, scaled to RAY precision
     * @dev This function assumes that the tranche token is an ERC4626 compliant vault
     * @dev The conversion rate is calculated as the value of tranche asset in base asset * value of base asset in NAV units
     * @return trancheToNAVUnitConversionRateRAY The conversion rate from tranche token units to NAV units, scaled to RAY precision
     */
    function getTrancheUnitToNAVUnitConversionRateRAY()
        public
        view
        virtual
        override(IdenticalAssetsOracleQuoter)
        returns (uint256 trancheToNAVUnitConversionRateRAY)
    {
        // Fetch the conversion rate from the tranche asset (ERC4626 share) to its underlying asset, scaled to RAY precision
        uint256 trancheUnitToBaseAssetsConversionRateRAY = IERC4626(ST_ASSET).convertToAssets(SHARES_TO_CONVERT_TO_ASSETS);

        // Resolve the vault base asset to NAV unit conversion rate, scaled to RAY precision
        uint256 baseAssetToNAVUnitConversionRateRAY = getStoredConversionRateRAY();
        // If the stored conversion rate is the sentinel value, the cache hasn't been warmed, so query the oracle for the rate
        if (baseAssetToNAVUnitConversionRateRAY == SENTINEL_CONVERSION_RATE) baseAssetToNAVUnitConversionRateRAY = _getConversionRateFromOracleRAY();

        // Calculate the conversion rate from tranche to NAV units, scaled to RAY precision
        trancheToNAVUnitConversionRateRAY = trancheUnitToBaseAssetsConversionRateRAY.mulDiv(baseAssetToNAVUnitConversionRateRAY, RAY, Math.Rounding.Floor);
    }
}
