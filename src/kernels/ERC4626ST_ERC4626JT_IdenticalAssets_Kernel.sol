// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { ERC4626JTKernel } from "./base/junior/ERC4626JTKernel.sol";
import { IdenticalAssetsQuoter } from "./base/quoter/IdenticalAssetsQuoter.sol";
import { ERC4626STKernel } from "./base/senior/ERC4626STKernel.sol";

contract ERC4626ST_ERC4626JT_IdenticalAssets_Kernel is ERC4626STKernel, ERC4626JTKernel, IdenticalAssetsQuoter {
    function initialize(RoycoKernelInitParams calldata _params, address _initialAuthority, address _stVault, address _jtVault) external initializer {
        // Get the base assets for both tranches and ensure that they are identical
        address stAsset = IRoycoVaultTranche(_params.seniorTranche).asset();
        address jtAsset = IRoycoVaultTranche(_params.juniorTranche).asset();

        // Initialize the base kernel state
        __RoycoKernel_init(_params, stAsset, jtAsset, _initialAuthority);
        // Initialize the ERC4626 senior tranche state
        __ERC4626_ST_Kernel_init_unchained(_stVault, stAsset);
        // Initialize the ERC4626 junior tranche state
        __ERC4626_JT_Kernel_init_unchained(_jtVault, stAsset);
        // Initialize the identical assets quoter
        __IdenticalAssetsQuoter_init_unchained(stAsset, jtAsset);
    }
}
