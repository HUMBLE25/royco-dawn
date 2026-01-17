// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { RoycoKernel } from "./base/RoycoKernel.sol";
import { YieldBearingERC20_JT_Kernel } from "./base/junior/YieldBearingERC20_JT_Kernel.sol";
import { IdenticalAssetsChainlinkOracleQuoter } from "./base/quoter/IdenticalAssetsChainlinkOracleQuoter.sol";
import { YieldBearingERC20_ST_Kernel } from "./base/senior/YieldBearingERC20_ST_Kernel.sol";

/**
 * @title YBERC4626_ST_YBERC4626_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel
 * @notice The senior and junior tranches transfer in the same yield bearing asset
 * @notice The kernel uses a Chainlink oracle to convert tranche token units to NAV units, allowing NAVs to sync based on underlying PNL
 */
contract YBERC4626_ST_YBERC4626_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel is
    YieldBearingERC20_ST_Kernel,
    YieldBearingERC20_JT_Kernel,
    IdenticalAssetsChainlinkOracleQuoter
{
    /// @notice Thrown when a function is not implemented
    error NOT_IMPLEMENTED();

    /// @notice Constructs the kernel state
    /// @param _params The standard construction parameters for the Royco kernel
    constructor(RoycoKernelConstructionParams memory _params) RoycoKernel(_params) { }

    /**
     * @notice Initializes the Royco Kernel
     * @param _params The standard initialization parameters for the Royco Kernel
     * @param _initialConversionRateWAD The initial tranche unit to NAV unit conversion rate
     */
    function __YBERC4626_ST_YBERC4626_JT_IdenticalAssetsChainlinkOracleQuoter_Kernel_init(
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

    function _getConversionRateFromOracle() internal view override returns (uint256) {
        revert NOT_IMPLEMENTED();
    }
}
