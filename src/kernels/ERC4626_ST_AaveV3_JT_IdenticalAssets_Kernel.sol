// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { AaveV3_JT_Kernel } from "./base/junior/AaveV3_JT_Kernel.sol";
import { IdenticalAssetsQuoter } from "./base/quoter/IdenticalAssetsQuoter.sol";
import { ERC4626_ST_Kernel } from "./base/senior/ERC4626_ST_Kernel.sol";

contract ERC4626_ST_AaveV3_JT_IdenticalAssets_Kernel is ERC4626_ST_Kernel, AaveV3_JT_Kernel, IdenticalAssetsQuoter {
    function initialize(RoycoKernelInitParams calldata _params, address _initialAuthority, address _stVault, address _aaveV3Pool) external initializer {
        // Get the base assets for both tranches and ensure that they are identical
        address stAsset = IRoycoVaultTranche(_params.seniorTranche).asset();
        address jtAsset = IRoycoVaultTranche(_params.juniorTranche).asset();

        // Initialize the base kernel state
        __RoycoKernel_init(_params, stAsset, jtAsset, _initialAuthority);
        // Initialize the ERC4626 senior tranche state
        __ERC4626_ST_Kernel_init_unchained(_stVault, stAsset);
        // Initialize the Aave V3 junior tranche state
        __AaveV3_JT_Kernel_init_unchained(_aaveV3Pool, jtAsset);
        // Initialize the identical assets quoter
        __IdenticalAssetsQuoter_init_unchained(stAsset, jtAsset);
    }
}
