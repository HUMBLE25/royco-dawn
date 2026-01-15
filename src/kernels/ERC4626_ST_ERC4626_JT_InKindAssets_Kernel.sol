// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../libraries/RoycoKernelStorageLib.sol";
import { NAV_UNIT } from "../libraries/Units.sol";
import { RoycoKernel } from "./base/RoycoKernel.sol";
import { InKindAssetsQuoter } from "./base/quoter/InKindAssetsQuoter.sol";
import { ERC4626_ST_ERC4626_JT_Kernel } from "./base/recipe/ERC4626_ST_ERC4626_JT_Kernel.sol";
import { ERC4626_ST_Kernel } from "./base/senior/ERC4626_ST_Kernel.sol";

/**
 * @title ERC4626_ST_ERC4626_JT_InKindAssets_Kernel
 * @notice The senior and junior tranches are deployed into a ERC4626 compliant vault
 * @notice The two tranches can be deployed into the same ERC4626 compliant vault
 * @notice The tranche assets are identical in value and can have differing precisions (eg. USDC and USDS, USDT and USDE, etc.)
 * @notice NAV units are always expressed in tranche units scaled to WAD (18 decimals) precision
 */
contract ERC4626_ST_ERC4626_JT_InKindAssets_Kernel is ERC4626_ST_ERC4626_JT_Kernel, InKindAssetsQuoter {
    /**
     * @notice Initializes the Royco Kernel
     * @param _stVault The ERC4626 compliant vault that the senior tranche will deploy into
     * @param _jtVault The ERC4626 compliant vault that the junior tranche will deploy into
     */
    function initialize(RoycoKernelInitParams calldata _params, address _stVault, address _jtVault) external initializer {
        // Get the base assets for both tranches and ensure that they are identical
        address stAsset = IRoycoVaultTranche(_params.seniorTranche).asset();
        address jtAsset = IRoycoVaultTranche(_params.juniorTranche).asset();

        // Initialize the base kernel state
        __ERC4626_ST_ERC4626_JT_Kernel_init(_params, _stVault, _jtVault);
        // Initialize the in kind assets quoter
        __InKindAssetsQuoter_init_unchained(stAsset, jtAsset);
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
