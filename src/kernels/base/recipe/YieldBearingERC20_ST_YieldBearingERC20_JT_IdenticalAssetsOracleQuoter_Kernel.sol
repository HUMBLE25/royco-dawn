// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../../../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../../../libraries/RoycoKernelStorageLib.sol";
import { RoycoKernel } from "../RoycoKernel.sol";
import { YieldBearingERC20_JT_Kernel } from "../junior/YieldBearingERC20_JT_Kernel.sol";
import { IdenticalAssetsOracleQuoter } from "../quoter/base/IdenticalAssetsOracleQuoter.sol";
import { YieldBearingERC20_ST_Kernel } from "../senior/YieldBearingERC20_ST_Kernel.sol";

/**
 * @title YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsOracleQuoter_Kernel
 * @notice The senior and junior tranches transfer in the same yield bearing ERC20 assets (sACRED, mF-ONE, reUSD, etc.)
 * @notice The kernel uses an overridable oracle to convert tranche units to NAV units, allowing NAVs to sync based on underlying PNL
 */
abstract contract YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsOracleQuoter_Kernel is
    YieldBearingERC20_ST_Kernel,
    YieldBearingERC20_JT_Kernel,
    IdenticalAssetsOracleQuoter
{
    /// @notice Constructs the kernel state
    /// @param _params The standard construction parameters for the Royco kernel
    constructor(RoycoKernelConstructionParams memory _params) RoycoKernel(_params) { }

    /**
     * @notice Initializes the Royco Kernel
     * @param _params The standard initialization parameters for the Royco Kernel
     * @param _initialConversionRateWAD The initial tranche unit to NAV unit conversion rate
     */
    function __YieldBearingERC20_ST_YieldBearingERC20_JT_IdenticalAssetsOracleQuoter_Kernel_init(
        RoycoKernelInitParams calldata _params,
        uint256 _initialConversionRateWAD
    )
        internal
        onlyInitializing
    {
        // Initialize the base kernel state
        __RoycoKernel_init(_params);
        // Initialize the overridable NAV oracle identical assets quoter
        __IdenticalAssetsOracleQuoter_init_unchained(_initialConversionRateWAD);
    }
}
