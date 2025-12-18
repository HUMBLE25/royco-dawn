// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { AaveV3JTKernel } from "./base/junior/AaveV3JTKernel.sol";
import { InKindAssetsQuoter } from "./base/quoter/InKindAssetsQuoter.sol";
import { ERC4626STKernel } from "./base/senior/ERC4626STKernel.sol";

contract ERC4626ST_AaveV3JT_InKindAssets_Kernel is ERC4626STKernel, AaveV3JTKernel, InKindAssetsQuoter {
    function initialize(
        RoycoKernelInitParams calldata _params,
        address _initialAuthority,
        address _stVault,
        address _aaveV3Pool,
        uint256 _jtRedemptionDelaySeconds
    )
        external
        initializer
    {
        // Get the base assets for both tranches and ensure that they are identical
        address stAsset = IRoycoVaultTranche(_params.seniorTranche).asset();
        address jtAsset = IRoycoVaultTranche(_params.juniorTranche).asset();

        // Initialize the base kernel state
        __RoycoKernel_init(_params, stAsset, jtAsset, _initialAuthority);
        // Initialize the in kind assets quoter
        __InKindAssetsQuoter_init_unchained(stAsset, jtAsset);
        // Initialize the ERC4626 senior tranche state
        __ERC4626_ST_Kernel_init_unchained(_stVault, stAsset);
        // Initialize the Aave V3 junior tranche state
        __AaveV3_JT_Kernel_init(_aaveV3Pool, jtAsset, _jtRedemptionDelaySeconds);
    }
}
