// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IERC7540 } from "../../../interfaces/tranche/IERC7540.sol";
import { BaseKernelState, BaseKernelStorageLib } from "../../../libraries/BaseKernelStorageLib.sol";
import { ConstantsLib } from "../../../libraries/ConstantsLib.sol";
import { ERC7540KernelState, ERC7540KernelStorageLib } from "../../../libraries/kernels/ERC7540KernelStorageLib.sol";
import { BaseKernel, IBaseKernel } from "../BaseKernel.sol";

abstract contract ERC7540STKernel is BaseKernel {
    using SafeERC20 for IERC20;

    /**
     * @notice Initializes a kernel where the junior tranche is deployed into Aave V3
     * @dev Mandates that the base kernel state is already initialized
     * @param _vault The address of the ERC7540 compliant vault
     */
    function __ERC7540STKernel_init_unchained(address _vault) internal onlyInitializing {
        // Extend a one time max approval to the ERC7540 vault for the JT's base asset
        address stAsset = IERC4626(BaseKernelStorageLib._getBaseKernelStorage().seniorTranche).asset();
        IERC20(stAsset).forceApprove(address(_vault), type(uint256).max);

        // Initialize the ERC7540 kernel storage
        ERC7540KernelStorageLib.__ERC7540Kernel_init(_vault, stAsset);
    }

    /// @inheritdoc IBaseKernel
    function stDeposit(
        address _asset,
        uint256 _assets,
        address _caller,
        address _receiver
    )
        external
        override(IBaseKernel)
        returns (uint256 underlyingSharesAllocated, uint256 totalUnderlyingShares)
    { }

    /// @inheritdoc IBaseKernel
    function stRedeem(
        address _asset,
        uint256 _shares,
        uint256 _totalShares,
        address _caller,
        address _receiver
    )
        external
        override(IBaseKernel)
        returns (uint256 assetsWithdrawn)
    { }

    /// @inheritdoc BaseKernel
    function _getSeniorTrancheRawNAV() internal view override(BaseKernel) returns (uint256) {
        address vault = ERC7540KernelStorageLib._getERC7540KernelStorage().vault;
        uint256 trancheShares = IERC4626(vault).balanceOf(address(this));
        return IERC4626(vault).previewRedeem(trancheShares);
    }

    /// @inheritdoc BaseKernel
    function _maxSTDepositGlobally(address) internal view override(BaseKernel) returns (uint256) {
        return IERC4626(ERC7540KernelStorageLib._getERC7540KernelStorage().vault).maxDeposit(address(this));
    }

    /// @inheritdoc BaseKernel
    function _maxSTWithdrawalGlobally(address) internal view override(BaseKernel) returns (uint256) {
        return IERC4626(ERC7540KernelStorageLib._getERC7540KernelStorage().vault).maxWithdraw(address(this));
    }
}
