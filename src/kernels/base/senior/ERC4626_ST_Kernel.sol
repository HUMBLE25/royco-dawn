// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { ExecutionModel, IRoycoKernel, SharesRedemptionModel } from "../../../interfaces/kernel/IRoycoKernel.sol";
import { AssetClaims, SyncedAccountingState } from "../../../libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT, UnitsMathLib, toTrancheUnits, toUint256 } from "../../../libraries/Units.sol";
import { ERC4626KernelState, ERC4626KernelStorageLib } from "../../../libraries/kernels/ERC4626KernelStorageLib.sol";
import { RoycoKernel, TrancheType } from "../RoycoKernel.sol";

abstract contract ERC4626_ST_Kernel is RoycoKernel {
    using SafeERC20 for IERC20;
    using UnitsMathLib for TRANCHE_UNIT;

    /// @notice Thrown when the ST base asset is different the the ERC4626 vault's base asset
    error SENIOR_TRANCHE_AND_VAULT_ASSET_MISMATCH();

    /// @inheritdoc IRoycoKernel
    ExecutionModel public constant ST_DEPOSIT_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @inheritdoc IRoycoKernel
    ExecutionModel public constant ST_REDEEM_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @inheritdoc IRoycoKernel
    SharesRedemptionModel public constant ST_REQUEST_REDEEM_SHARES_BEHAVIOR = SharesRedemptionModel.BURN_ON_CLAIM_REDEEM;

    /// @notice Immutable address for the ST ERC4626 vault
    address internal immutable ST_VAULT;

    constructor(address _stVault) {
        // Ensure that the ST base asset is identical to the ERC4626 vault's base asset
        require(IERC4626(_stVault).asset() == ST_ASSET, SENIOR_TRANCHE_AND_VAULT_ASSET_MISMATCH());

        // Set the immutable address for the ST ERC4626 vault
        ST_VAULT = _stVault;
    }

    /// @notice Initializes a kernel where the senior tranche is deployed into an ERC4626 vault
    function __ERC4626_ST_Kernel_init_unchained() internal onlyInitializing {
        // Extend a one time max approval to the ERC4626 vault for the ST's base asset
        IERC20(ST_ASSET).forceApprove(ST_VAULT, type(uint256).max);
    }

    /// @inheritdoc IRoycoKernel
    function stPreviewDeposit(TRANCHE_UNIT _assets) external view override returns (SyncedAccountingState memory stateBeforeDeposit, NAV_UNIT valueAllocated) {
        // Simulate the deposit of the assets into the underlying investment vault
        uint256 stVaultSharesMinted = IERC4626(ST_VAULT).previewDeposit(toUint256(_assets));

        // Convert the underlying vault shares to tranche units. This value may differ from _assets if a fee or slippage is incurred to the deposit.
        TRANCHE_UNIT stAssetsAllocated = toTrancheUnits(IERC4626(ST_VAULT).convertToAssets(stVaultSharesMinted));

        // Convert the assets allocated to NAV units and preview a sync to get the current NAV to mint shares at for the senior tranche
        valueAllocated = stConvertTrancheUnitsToNAVUnits(stAssetsAllocated);
        stateBeforeDeposit = _previewSyncTrancheAccounting();
    }

    /// @inheritdoc IRoycoKernel
    function stPreviewRedeem(uint256 _shares) external view override returns (AssetClaims memory userClaim) {
        userClaim = _previewRedeem(_shares, TrancheType.SENIOR);
    }

    /// @inheritdoc RoycoKernel
    function _getSeniorTrancheRawNAV() internal view override(RoycoKernel) returns (NAV_UNIT) {
        ERC4626KernelState storage $ = ERC4626KernelStorageLib._getERC4626KernelStorage();
        // Must use convert to assets for the tranche owned shares in order to be exlusive of any fixed fees on withdrawal
        // Cannot use max withdraw since it will treat illiquidity as a NAV loss
        TRANCHE_UNIT stOwnedAssets = toTrancheUnits(IERC4626(ST_VAULT).convertToAssets($.stOwnedShares));
        return stConvertTrancheUnitsToNAVUnits(stOwnedAssets);
    }

    /// @inheritdoc RoycoKernel
    function _stMaxDepositGlobally(address) internal view override(RoycoKernel) returns (TRANCHE_UNIT) {
        // Max deposit takes global withdrawal limits into account
        return toTrancheUnits(IERC4626(ST_VAULT).maxDeposit(address(this)));
    }

    /// @inheritdoc RoycoKernel
    function _stMaxWithdrawableGlobally(address) internal view override(RoycoKernel) returns (TRANCHE_UNIT) {
        // Max withdraw takes global withdrawal limits into account
        return toTrancheUnits(IERC4626(ST_VAULT).maxWithdraw(address(this)));
    }

    /// @inheritdoc RoycoKernel
    function _stPreviewWithdraw(TRANCHE_UNIT _stAssets) internal view override(RoycoKernel) returns (TRANCHE_UNIT withdrawnSTAssets) {
        // Convert the ST assets to underlying shares
        uint256 stVaultShares = IERC4626(ST_VAULT).convertToShares(toUint256(_stAssets));
        // Preview the amount of ST assets that would be redeemed for the given amount of underlying shares
        withdrawnSTAssets = toTrancheUnits(IERC4626(ST_VAULT).previewRedeem(stVaultShares));
    }

    /// @inheritdoc RoycoKernel
    function _stDepositAssets(TRANCHE_UNIT _stAssets) internal override(RoycoKernel) {
        // Deposit the assets into the underlying investment vault and add to the number of ST controlled shares for this vault
        ERC4626KernelState storage $ = ERC4626KernelStorageLib._getERC4626KernelStorage();
        $.stOwnedShares += IERC4626(ST_VAULT).deposit(toUint256(_stAssets), address(this));
    }

    /// @inheritdoc RoycoKernel
    function _stWithdrawAssets(TRANCHE_UNIT _stAssets, address _receiver) internal override(RoycoKernel) {
        ERC4626KernelState storage $ = ERC4626KernelStorageLib._getERC4626KernelStorage();
        // Get the currently withdrawable liquidity from the vault
        TRANCHE_UNIT maxWithdrawableAssets = toTrancheUnits(IERC4626(ST_VAULT).maxWithdraw(address(this)));
        // If the vault has sufficient liquidity to withdraw the specified assets, do so
        if (maxWithdrawableAssets >= _stAssets) {
            $.stOwnedShares -= IERC4626(ST_VAULT).withdraw(toUint256(_stAssets), _receiver, address(this));
            // If the vault has insufficient liquidity to withdraw the specified assets, transfer the equivalent number of shares to the receiver
        } else {
            // Transfer the assets equivalent of shares to the receiver
            uint256 sharesEquivalentToWithdraw = IERC4626(ST_VAULT).convertToShares(toUint256(_stAssets));
            $.stOwnedShares -= sharesEquivalentToWithdraw;
            IERC20(address(ST_VAULT)).safeTransfer(_receiver, sharesEquivalentToWithdraw);
        }
    }
}
