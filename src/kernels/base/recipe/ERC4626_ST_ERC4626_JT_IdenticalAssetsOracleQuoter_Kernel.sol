// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { RoycoKernelInitParams } from "../../../libraries/RoycoKernelStorageLib.sol";
import { NAV_UNIT } from "../../../libraries/Units.sol";
import { RoycoKernel } from "../RoycoKernel.sol";
import { IdenticalAssetsOracleQuoter } from "../quoter/base/IdenticalAssetsOracleQuoter.sol";
import { ERC4626_ST_ERC4626_JT_Kernel } from "./ERC4626_ST_ERC4626_JT_Kernel.sol";

/**
 * @title ERC4626_ST_ERC4626_JT_IdenticalAssetsOracleQuoter_Kernel
 * @notice The senior and junior tranches are deployed into a ERC4626 compliant vault
 * @notice The two tranches can be deployed into the same ERC4626 compliant vault
 * @notice The tranche assets are identical in value and precision (eg. USDC for both tranches, USDC and USDT, etc.)
 * @notice Tranche and NAV units are always expressed in the tranche asset's precision. The NAV Unit factors in a conversion rate from the overridable NAV Conversion Rate oracle.
 */
abstract contract ERC4626_ST_ERC4626_JT_IdenticalAssetsOracleQuoter_Kernel is ERC4626_ST_ERC4626_JT_Kernel, IdenticalAssetsOracleQuoter {
    /**
     * @notice Constructs the Royco kernel
     * @param _params The standard construction parameters for the Royco kernel
     * @param _stVault The address of the ERC4626 compliant vault that the senior tranche will deploy into
     * @param _jtVault The address of the ERC4626 compliant vault that the junior tranche will deploy into
     */
    constructor(RoycoKernelConstructionParams memory _params, address _stVault, address _jtVault) ERC4626_ST_ERC4626_JT_Kernel(_params, _stVault, _jtVault) { }

    /**
     * @notice Initializes the Royco Kernel
     * @param _params The standard initialization parameters for the Royco Kernel
     * @param _initialConversionRateWAD The initial tranche unit to NAV unit conversion rate
     */
    function __ERC4626_ST_ERC4626_JT_IdenticalAssetsOracleQuoter_Kernel_init(
        RoycoKernelInitParams calldata _params,
        uint256 _initialConversionRateWAD
    )
        internal
        onlyInitializing
    {
        // Initialize the base kernel state
        __ERC4626_ST_ERC4626_JT_Kernel_init(_params);
        // Initialize the overridable NAV oracle identical assets quoter
        __IdenticalAssetsOracleQuoter_init_unchained(_initialConversionRateWAD);
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

