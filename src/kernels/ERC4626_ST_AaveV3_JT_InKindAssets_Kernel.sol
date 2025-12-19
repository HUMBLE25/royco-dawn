// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { AaveV3_JT_Kernel } from "./base/junior/AaveV3_JT_Kernel.sol";
import { InKindAssetsQuoter } from "./base/quoter/InKindAssetsQuoter.sol";
import { ERC4626_ST_Kernel } from "./base/senior/ERC4626_ST_Kernel.sol";

/**
 * @title ERC4626_ST_AaveV3_JT_InKindAssets_Kernel
 * @notice The senior tranche is deployed into a ERC4626 compliant vault and the junior tranche is deployed into Aave V3
 * @notice The tranche assets are identical in value and can have differing precisions (eg. USDC and USDS, USDT and USDE, etc.)
 * @notice Tranche units are always expressed in the tranche's assets precision
 * @notice NAV units are always expressed in tranche units scaled to WAD (18 decimals) precision
 */
contract ERC4626_ST_AaveV3_JT_InKindAssets_Kernel is ERC4626_ST_Kernel, AaveV3_JT_Kernel, InKindAssetsQuoter {
    /**
     * @notice Initializes the Royco Kernel
     * @param _params The standard initialization parameters for the Royco Kernel
     * @param _stVault The ERC4626 compliant vault that the senior tranche will deploy into
     * @param _aaveV3Pool The Aave V3 Pool that the junior tranche will deploy into
     */
    function initialize(RoycoKernelInitParams calldata _params, address _stVault, address _aaveV3Pool) external initializer {
        // Get the base assets for both tranches and ensure that they are identical
        address stAsset = IRoycoVaultTranche(_params.seniorTranche).asset();
        address jtAsset = IRoycoVaultTranche(_params.juniorTranche).asset();

        // Initialize the base kernel state
        __RoycoKernel_init(_params, stAsset, jtAsset);
        // Initialize the ERC4626 senior tranche state
        __ERC4626_ST_Kernel_init_unchained(_stVault, stAsset);
        // Initialize the Aave V3 junior tranche state
        __AaveV3_JT_Kernel_init_unchained(_aaveV3Pool, jtAsset);
        // Initialize the in kind assets quoter
        __InKindAssetsQuoter_init_unchained(stAsset, jtAsset);
    }
}
