// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BaseKernelInitParams } from "../libraries/BaseKernelStorageLib.sol";
import { AaveV3JTKernel } from "./base/junior/AaveV3JTKernel.sol";
import { ERC4626STKernel } from "./base/senior/ERC4626STKernel.sol";

contract ERC4626ST_AaveV3JT_Kernel is ERC4626STKernel, AaveV3JTKernel {
    function initialize(BaseKernelInitParams calldata _params, address _stVault, address _aaveV3Pool) external initializer {
        // Initialize the base kernel state
        __BaseKernel_init(_params);
        // Initialize the ERC4626 senior tranche state
        __ERC4626STKernel_init_unchained(_stVault);
        // Initialize the Aave V3 junior tranche state
        __AaveV3JTKernel_init_unchained(_aaveV3Pool);
    }
}
