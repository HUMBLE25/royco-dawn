// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { WAD } from "../libraries/Constants.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { IdenticalAssetsOracleQuoter } from "./base/quoter/IdenticalAssetsOracleQuoter.sol";
import {
    ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel
} from "./base/recipe/ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel.sol";

/**
 * @title ERC4626_ST_ERC4626_JT_FixedTrancheToNAVConversionRateIdenticalAssets_Kernel
 * @notice The senior and junior tranches are deployed into a ERC4626 compliant vault
 * @notice The two tranches can be deployed into the same ERC4626 compliant vault
 * @notice Tranche and NAV units are always expressed in the tranche asset's precision. The NAV Unit factors in a conversion rate from the overridable NAV Conversion Rate oracle.
 */
contract ERC4626_ST_ERC4626_JT_FixedTrancheToNAVConversionRateIdenticalAssets_Kernel is ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel {
    /// @notice Thrown when the function is not implemented
    error NOT_IMPLEMENTED();

    /// @notice Constructor
    /// @param _seniorTranche The address of the senior tranche
    /// @param _juniorTranche The address of the junior tranche
    /// @param _snUSDVault The address of the SNUSD vault
    constructor(
        address _seniorTranche,
        address _juniorTranche,
        address _snUSDVault
    )
        ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel(_seniorTranche, _juniorTranche, _snUSDVault, _snUSDVault)
    { }

    /// @notice Initializes the kernel
    /// @param _params The standard initialization parameters for the Royco Kernel
    /// @param _initialConversionRateWAD The initial tranche unit to NAV unit conversion rate
    function initialize(RoycoKernelInitParams calldata _params, uint256 _initialConversionRateWAD) external initializer {
        __ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel_init(_params, _initialConversionRateWAD);
    }

    /// @inheritdoc IdenticalAssetsOracleQuoter
    function _getTrancheUnitToNAVUnitConversionRateFromOracle() internal pure override returns (uint256) {
        revert NOT_IMPLEMENTED();
    }
}
