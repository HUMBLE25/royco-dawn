// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { RoycoKernel } from "./base/RoycoKernel.sol";
import { AaveV3_JT_Kernel } from "./base/junior/AaveV3_JT_Kernel.sol";
import { IdenticalAssetsQuoter } from "./base/quoter/IdenticalAssetsQuoter.sol";
import { ERC4626_ST_Kernel } from "./base/senior/ERC4626_ST_Kernel.sol";

/**
 * @title ERC4626_ST_AaveV3_JT_IdenticalAssets_Kernel
 * @notice The senior tranche is deployed into a ERC4626 compliant vault and the junior tranche is deployed into Aave V3
 * @notice The tranche assets are identical in value and precision (eg. USDC for both tranches, USDC and USDT, etc.)
 * @notice Tranche and NAV units are always expressed in the tranche asset's precision
 */
contract ERC4626_ST_AaveV3_JT_IdenticalAssets_Kernel is ERC4626_ST_Kernel, AaveV3_JT_Kernel, IdenticalAssetsQuoter {
    constructor(
        address _seniorTranche,
        address _juniorTranche,
        address _stVault,
        address _aaveV3Pool
    )
        ERC4626_ST_Kernel(_stVault)
        AaveV3_JT_Kernel(_aaveV3Pool)
        RoycoKernel(_seniorTranche, IERC4626(_stVault).asset(), _juniorTranche, IERC4626(_stVault).asset())
    { }

    /**
     * @notice Initializes the Royco Kernel
     * @param _params The standard initialization parameters for the Royco Kernel
     */
    function initialize(RoycoKernelInitParams calldata _params) external initializer {
        // Initialize the base kernel state
        __RoycoKernel_init(_params);
        // Initialize the ERC4626 senior tranche state
        __ERC4626_ST_Kernel_init_unchained();
        // Initialize the Aave V3 junior tranche state
        __AaveV3_JT_Kernel_init_unchained();
    }
}
