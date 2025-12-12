// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { ExecutionModel, IBaseKernel } from "../../../interfaces/kernel/IBaseKernel.sol";
import { BaseKernelState, BaseKernelStorageLib, Operation } from "../../../libraries/BaseKernelStorageLib.sol";
import { ConstantsLib } from "../../../libraries/ConstantsLib.sol";
import { ERC4626STKernelStorageLib } from "../../../libraries/kernels/ERC4626STKernelStorageLib.sol";
import { BaseKernel } from "../BaseKernel.sol";

abstract contract ERC4626STKernel is BaseKernel {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @inheritdoc IBaseKernel
    ExecutionModel public constant ST_DEPOSIT_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @inheritdoc IBaseKernel
    ExecutionModel public constant ST_WITHDRAWAL_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @notice Thrown when the ST base asset is different the the ERC4626 vault's base asset
    error TRANCHE_AND_VAULT_ASSET_MISMATCH();

    /**
     * @notice Initializes a kernel where the senior tranche is deployed into an ERC4626 vault
     * @dev Mandates that the base kernel state is already initialized
     * @param _vault The address of the ERC4626 compliant vault
     * @param _stAsset The address of the base asset of the senior tranche
     */
    function __ERC4626STKernel_init_unchained(address _vault, address _stAsset) internal onlyInitializing {
        // Ensure that the ST base asset is identical to the ERC4626 vault's base asset
        require(IERC4626(_vault).asset() == _stAsset, TRANCHE_AND_VAULT_ASSET_MISMATCH());

        // Extend a one time max approval to the ERC4626 vault for the ST's base asset
        IERC20(_stAsset).forceApprove(address(_vault), type(uint256).max);

        // Initialize the ERC4626 ST kernel storage
        ERC4626STKernelStorageLib.__ERC4626STKernel_init(_vault, _stAsset);
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
        whenNotPaused
        syncNAVsAndEnforceCoverage(Operation.ST_DEPOSIT)
        returns (uint256 valueAllocated, uint256 effectiveNAVToMintAt)
    {
        // Deposit the assets into the underlying investment vault
        address vault = ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault;

        // Deposit the assets into the underlying investment vault
        IERC4626(vault).deposit(_assets, address(this));

        // The value of the assets deposited is the value of the assets in the asset that the tranche's NAV is denominated in
        valueAllocated = _convertAssetsToValue(_assets);

        // The effective NAV to mint at is the effective NAV of the tranche before the deposit is made, ie. the NAV at which the shares will be minted
        effectiveNAVToMintAt = _getSeniorTrancheEffectiveNAV();
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
        whenNotPaused
        syncNAVs(Operation.ST_WITHDRAW)
        returns (uint256 assetsWithdrawn)
    {
        // Get the storage pointer to the base kernel state
        // We can assume that all NAV and debt values are synced
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();
        // Compute the assets expected to be received on withdrawal based on the ST's effective NAV
        assetsWithdrawn = _shares.mulDiv($.lastSTEffectiveNAV, _totalShares, Math.Rounding.Floor);

        // Compute the coverage that needs to pulled from JT for this withdrawal, rounding in favor of ST
        uint256 coverageToRealize = _shares.mulDiv(BaseKernelStorageLib._getBaseKernelStorage().lastSTCoverageDebt, _totalShares, Math.Rounding.Ceil);
        coverageToRealize = Math.min(coverageToRealize, _getJuniorTrancheRawNAV());
        // Pull any coverge that needs to be realized from JT
        if (coverageToRealize != 0) _coverSTLossesFromJT(_asset, coverageToRealize, _receiver);

        // Facilitate the remainder of the withdrawal from ST exposure
        IERC4626(ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault).withdraw((assetsWithdrawn - coverageToRealize), _receiver, address(this));
    }

    /**
     * @notice Converts the amount of assets to the value of the assets in the asset that the tranche's NAV is denominated in
     * @dev This implementation assumes that the NAV is denominated in the same asset as the assets being deposited
     * @param _assets The amount of assets to convert
     * @return value The value of the assets in the asset that the tranche's NAV is denominated in
     */
    function _convertAssetsToValue(uint256 _assets) internal view virtual returns (uint256 value) {
        return _assets;
    }

    /// @inheritdoc BaseKernel
    function _claimJTYieldFromST(address, uint256 _yieldAssets, address _receiver) internal override(BaseKernel) {
        IERC4626(ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault).withdraw(_yieldAssets, _receiver, address(this));
    }

    /// @inheritdoc BaseKernel
    function _getSeniorTrancheRawNAV() internal view override(BaseKernel) returns (uint256) {
        // Must use preview redeem for the tranche owned shares
        // Max withdraw will mistake illiquidity for NAV losses
        address vault = ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault;
        uint256 trancheSharesBalance = IERC4626(vault).balanceOf(address(this));
        return IERC4626(vault).previewRedeem(trancheSharesBalance);
    }

    /// @inheritdoc BaseKernel
    function _maxSTDepositGlobally(address) internal view override(BaseKernel) returns (uint256) {
        // Max deposit takes global withdrawal limits into account
        return IERC4626(ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault).maxDeposit(address(this));
    }

    /// @inheritdoc BaseKernel
    function _maxSTWithdrawalGlobally(address) internal view override(BaseKernel) returns (uint256) {
        // Max withdraw takes global withdrawal limits into account
        return IERC4626(ERC4626STKernelStorageLib._getERC4626STKernelStorage().vault).maxWithdraw(address(this));
    }
}
