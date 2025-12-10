// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { ExecutionModel, IBaseKernel } from "../../../interfaces/kernel/IBaseKernel.sol";
import { BaseKernelState, BaseKernelStorageLib } from "../../../libraries/BaseKernelStorageLib.sol";
import { ConstantsLib } from "../../../libraries/ConstantsLib.sol";
import { ERC4626STKernelState, ERC4626STKernelStorageLib } from "../../../libraries/kernels/ERC4626STKernelStorageLib.sol";
import { BaseKernel } from "../BaseKernel.sol";

abstract contract ERC4626STKernel is BaseKernel {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @inheritdoc IBaseKernel
    ExecutionModel public constant ST_DEPOSIT_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @inheritdoc IBaseKernel
    ExecutionModel public constant ST_WITHDRAWAL_EXECUTION_MODEL = ExecutionModel.SYNC;

    /**
     * @notice Initializes a kernel where the senior tranche is deployed into an ERC4626 vault
     * @dev Mandates that the base kernel state is already initialized
     * @param _vault The address of the ERC4626 compliant vault
     */
    function __ERC4626STKernel_init_unchained(address _vault) internal onlyInitializing {
        // Extend a one time max approval to the ERC4626 vault for the ST's base asset
        address stAsset = IERC4626(BaseKernelStorageLib._getBaseKernelStorage().seniorTranche).asset();
        IERC20(stAsset).forceApprove(address(_vault), type(uint256).max);

        // Initialize the ERC4626 ST kernel storage
        ERC4626STKernelStorageLib.__ERC4626STKernel_init(_vault, stAsset);
    }

    /// @inheritdoc IBaseKernel
    function getSTTotalEffectiveAssets() external view override(IBaseKernel) returns (uint256) {
        return _getSeniorTrancheEffectiveNAV();
    }

    /// @inheritdoc IBaseKernel
    function stDeposit(
        address,
        uint256 _assets,
        address,
        address
    )
        external
        override(IBaseKernel)
        onlySeniorTranche
        syncNAVsAndEnforceCoverage
        returns (uint256 fractionOfTotalAssetsAllocatedWAD)
    {
        // Deposit the assets into the underlying investment vault
        address vault = ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault;
        uint256 underlyingSharesMinted = IERC4626(vault).deposit(_assets, address(this));
        // Return the fraction of the underlying exposure created by this deposit
        return underlyingSharesMinted.mulDiv(ConstantsLib.WAD, IERC4626(vault).balanceOf(address(this)), Math.Rounding.Floor);
    }

    /// @inheritdoc IBaseKernel
    function stRedeem(
        address _asset,
        uint256 _shares,
        uint256 _totalShares,
        address,
        address _receiver
    )
        external
        override(IBaseKernel)
        onlySeniorTranche
        syncNAVs
        returns (uint256 assetsWithdrawn)
    {
        // Get the assets expected to be received on withdrawal based on the ST's effective NAV
        uint256 totalAssetsToWithdraw = _shares.mulDiv(_getSeniorTrancheEffectiveNAV(), _totalShares, Math.Rounding.Floor);
        // Compute the coverage that needs to pulled from JT in this withdrawal
        uint256 coverageToRealize = _shares.mulDiv(BaseKernelStorageLib._getBaseKernelStorage().lastSTCoverageDebt, _totalShares, Math.Rounding.Ceil);
        // Pull any coverge that needs to be realized from JT
        assetsWithdrawn += _coverSTLossesFromJT(_asset, coverageToRealize, _receiver);
        totalAssetsToWithdraw -= assetsWithdrawn;
        // Pull the remainder from ST exposure
        uint256 stLiquidatableAssets = _getSeniorTrancheRawNAV();
        uint256 stAssetsToWithdraw = totalAssetsToWithdraw > stLiquidatableAssets ? stLiquidatableAssets : totalAssetsToWithdraw;
        IERC4626(ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault).withdraw(stAssetsToWithdraw, _receiver, address(this));
        assetsWithdrawn += stAssetsToWithdraw;
    }

    /// @inheritdoc BaseKernel
    function _getSeniorTrancheRawNAV() internal view override(BaseKernel) returns (uint256) {
        address vault = ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault;
        return IERC4626(vault).maxWithdraw(address(this));
    }

    /// @inheritdoc BaseKernel
    function _maxSTDepositGlobally(address) internal view override(BaseKernel) returns (uint256) {
        return IERC4626(ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault).maxDeposit(address(this));
    }

    /// @inheritdoc BaseKernel
    function _maxSTWithdrawalGlobally(address) internal view override(BaseKernel) returns (uint256) {
        return _getSeniorTrancheRawNAV();
    }
}
