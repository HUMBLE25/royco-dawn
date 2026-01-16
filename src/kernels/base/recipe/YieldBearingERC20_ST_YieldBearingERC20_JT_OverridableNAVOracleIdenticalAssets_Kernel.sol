// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../../../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../../../libraries/RoycoKernelStorageLib.sol";
import { RoycoKernel } from "../RoycoKernel.sol";
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
    /// @notice Thrown when the senior and junior tranche assets are different
    error ASSET_MISMATCH();

    /**
     * @notice Constructor for the YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel
     * @param _seniorTranche The address of the senior tranche
     * @param _juniorTranche The address of the junior tranche
     * @param _asset The address of the yield breaking ERC20 asset that the senior and junior tranches will transfer in
     */
    constructor(address _seniorTranche, address _juniorTranche, address _asset) RoycoKernel(_seniorTranche, _asset, _juniorTranche, _asset) {
        require(IRoycoVaultTranche(_seniorTranche).asset() == _asset && IRoycoVaultTranche(_juniorTranche).asset() == _asset, ASSET_MISMATCH());
    }

    /**
     * @notice Initializes the Royco Kernel
     * @param _params The standard initialization parameters for the Royco Kernel
     * @param _initialConversionRateWAD The initial tranche unit to NAV unit conversion rate
     */
    function __YieldBearingERC20_ST_YieldBearingERC20_JT_OverridableNAVOracleIdenticalAssets_Kernel_init_unchained(
        RoycoKernelInitParams calldata _params,
        uint256 _initialConversionRateWAD
    )
        internal
        onlyInitializing
    {
        // Initialize the base kernel state
        __RoycoKernel_init(_params);
        // Initialize the overridable NAV oracle identical assets quoter
        __OverridableNAVOracleIdenticalAssetsQuoter_init_unchained(_initialConversionRateWAD);
    }
}
