// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { RoycoKernelInitParams } from "../../../libraries/RoycoKernelStorageLib.sol";
import { YieldBearingERC20_JT_Kernel } from "../junior/YieldBearingERC20_JT_Kernel.sol";
import { OverridableNAVOracleIdenticalAssetsQuoter } from "../quoter/OverridableNAVOracleIdenticalAssetsQuoter.sol";
import { YieldBearingERC20_ST_Kernel } from "../senior/YieldBearingERC20_ST_Kernel.sol";

/**
 * @title YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel
 * @notice The senior and junior tranches transfer in the same yield breaking ERC20 assets.
 * @notice The kernel uses an overridable NAV Conversion Rate oracle to convert the Tranche Units to NAV Units.
 */
abstract contract YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel is
    YieldBearingERC20_ST_Kernel,
    YieldBearingERC20_JT_Kernel,
    OverridableNAVOracleIdenticalAssetsQuoter
{
    /**
     * @notice Initializes the Royco Kernel
     * @param _asset The address of the yield breaking ERC20 asset that the senior and junior tranches will transfer in
     * @param _initialConversionRateWAD The initial tranche unit to NAV unit conversion rate
     */
    function __YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel_init_unchained(
        RoycoKernelInitParams calldata _params,
        address _asset,
        uint256 _initialConversionRateWAD
    )
        internal
        onlyInitializing
    {
        // Initialize the base kernel state
        __RoycoKernel_init(_params, _asset, _asset);
        // Initialize the yield breaking ERC20 senior tranche state
        __YieldBearingERC20_ST_Kernel_init_unchained();
        // Initialize the yield breaking ERC20 junior tranche state
        __YieldBearingERC20_JT_Kernel_init_unchained();
        // Initialize the overridable NAV oracle identical assets quoter
        __OverridableNAVOracleIdenticalAssetsQuoter_init_unchained(_asset, _asset, _initialConversionRateWAD);
    }
}
