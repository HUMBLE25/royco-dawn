// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { NAV_UNIT } from "../libraries/Units.sol";
import { RoycoKernel } from "./base/RoycoKernel.sol";
import { IdenticalAssetsQuoter } from "./base/quoter/IdenticalAssetsQuoter.sol";
import { ERC4626_ST_ERC4626_JT_Kernel } from "./base/recipe/ERC4626_ST_ERC4626_JT_Kernel.sol";

/**
 * @title ERC4626_ST_ERC4626_JT_IdenticalAssets_Kernel
 * @notice The senior and junior tranches are deployed into a ERC4626 compliant vault
 * @notice The two tranches can be deployed into the same ERC4626 compliant vault
 * @notice The tranche assets are identical in value and precision (eg. USDC for both tranches, USDC and USDT, etc.)
 * @notice Tranche and NAV units are always expressed in the tranche asset's precision
 */
contract ERC4626_ST_ERC4626_JT_IdenticalAssets_Kernel is ERC4626_ST_ERC4626_JT_Kernel, IdenticalAssetsQuoter {
    /**
     * @notice Constructor for the ERC4626_ST_ERC4626_JT_IdenticalAssets_Kernel
     * @param _seniorTranche The address of the senior tranche
     * @param _juniorTranche The address of the junior tranche
     * @param _stVault The address of the ERC4626 compliant vault that the senior tranche will deploy into
     * @param _jtVault The address of the ERC4626 compliant vault that the junior tranche will deploy into
     */
    constructor(
        address _seniorTranche,
        address _juniorTranche,
        address _stVault,
        address _jtVault
    )
        ERC4626_ST_ERC4626_JT_Kernel(_seniorTranche, _juniorTranche, _stVault, _jtVault)
        IdenticalAssetsQuoter()
    { }

    /**
     * @notice Initializes the Royco Kernel
     * @param _params The standard initialization parameters for the Royco Kernel
     */
    function initialize(RoycoKernelInitParams calldata _params) external initializer {
        // Initialize the base kernel state
        __ERC4626_ST_ERC4626_JT_Kernel_init(_params);
    }

    /// @inheritdoc ERC4626_ST_ERC4626_JT_Kernel
    function stMaxWithdrawable(address _owner)
        public
        view
        virtual
        override(RoycoKernel, ERC4626_ST_ERC4626_JT_Kernel)
        returns (NAV_UNIT claimOnStNAV, NAV_UNIT claimOnJtNAV, NAV_UNIT stMaxWithdrawableNAV, NAV_UNIT jtMaxWithdrawableNAV)
    {
        return ERC4626_ST_ERC4626_JT_Kernel.stMaxWithdrawable(_owner);
    }

    /// @inheritdoc ERC4626_ST_ERC4626_JT_Kernel
    function jtMaxWithdrawable(address _owner)
        public
        view
        virtual
        override(RoycoKernel, ERC4626_ST_ERC4626_JT_Kernel)
        returns (NAV_UNIT claimOnStNAV, NAV_UNIT claimOnJtNAV, NAV_UNIT stMaxWithdrawableNAV, NAV_UNIT jtMaxWithdrawableNAV)
    {
        return ERC4626_ST_ERC4626_JT_Kernel.jtMaxWithdrawable(_owner);
    }
}

