// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRoycoVaultTranche } from "../../../interfaces/tranche/IRoycoVaultTranche.sol";
import { RoycoKernelInitParams } from "../../../libraries/RoycoKernelStorageLib.sol";
import { NAV_UNIT } from "../../../libraries/Units.sol";
import { RoycoKernel } from "../RoycoKernel.sol";
import { OverridableNAVOracleIdenticalAssetsQuoter } from "../quoter/OverridableNAVOracleIdenticalAssetsQuoter.sol";
import { ERC4626_ST_ERC4626_JT_Kernel } from "./ERC4626_ST_ERC4626_JT_Kernel.sol";

/**
 * @title ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel
 * @notice The senior and junior tranches are deployed into a ERC4626 compliant vault
 * @notice The two tranches can be deployed into the same ERC4626 compliant vault
 * @notice The tranche assets are identical in value and precision (eg. USDC for both tranches, USDC and USDT, etc.)
 * @notice Tranche and NAV units are always expressed in the tranche asset's precision. The NAV Unit factors in a conversion rate from the overridable NAV Conversion Rate oracle.
 */
abstract contract ERC4626_ST_ERC4626_JT_OverridableNAVOracleIdenticalAssets_Kernel is ERC4626_ST_ERC4626_JT_Kernel, OverridableNAVOracleIdenticalAssetsQuoter {
    /**
     * @notice Initializes the Royco Kernel
     * @param _stVault The ERC4626 compliant vault that the senior tranche will deploy into
     * @param _jtVault The ERC4626 compliant vault that the junior tranche will deploy into
     */
    function initialize(RoycoKernelInitParams calldata _params, address _stVault, address _jtVault, uint256 _initialConversionRateWAD) external initializer {
        // Get the base assets for both tranches and ensure that they are identical
        address stAsset = IRoycoVaultTranche(_params.seniorTranche).asset();
        address jtAsset = IRoycoVaultTranche(_params.juniorTranche).asset();

        // Initialize the base kernel state
        __ERC4626_ST_ERC4626_JT_Kernel_init(_params, _stVault, _jtVault);
        // Initialize the overridable NAV oracle identical assets quoter
        __OverridableNAVOracleIdenticalAssetsQuoter_init_unchained(stAsset, jtAsset, _initialConversionRateWAD);
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

