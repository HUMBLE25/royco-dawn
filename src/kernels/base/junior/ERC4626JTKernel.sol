// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC4626 } from "../../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { ExecutionModel, IRoycoKernel, RequestRedeemSharesBehavior } from "../../../interfaces/kernel/IRoycoKernel.sol";
import { ZERO_TRANCHE_UNITS } from "../../../libraries/Constants.sol";
import { SyncedAccountingState } from "../../../libraries/Types.sol";
import { AssetClaims } from "../../../libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT, UnitsMathLib, toTrancheUnits, toUint256 } from "../../../libraries/Units.sol";
import { UtilsLib } from "../../../libraries/UtilsLib.sol";
import { ERC4626KernelState, ERC4626KernelStorageLib } from "../../../libraries/kernels/ERC4626KernelStorageLib.sol";
import { Operation, RoycoKernel, TrancheType } from "../RoycoKernel.sol";
import { RedemptionDelayJTKernel } from "./base/RedemptionDelayJTKernel.sol";

abstract contract ERC4626JTKernel is RoycoKernel, RedemptionDelayJTKernel {
    using SafeERC20 for IERC20;
    using UnitsMathLib for TRANCHE_UNIT;

    /// @inheritdoc IRoycoKernel
    ExecutionModel public constant JT_DEPOSIT_EXECUTION_MODEL = ExecutionModel.SYNC;

    /// @notice Thrown when the ST base asset is different the the ERC4626 vault's base asset
    error TRANCHE_AND_VAULT_ASSET_MISMATCH();

    /// @notice Thrown when the shares to redeem are greater than the claimable shares
    error INSUFFICIENT_CLAIMABLE_SHARES(uint256 sharesToRedeem, uint256 claimableShares);

    /**
     * @notice Initializes a kernel where the junior tranche is deployed into an ERC4626 vault
     * @param _jtVault The address of the ERC4626 compliant vault the junior tranche will deploy into
     * @param _jtAsset The address of the base asset of the junior tranche
     * @param _jtRedemptionDelaySeconds The delay in seconds between a junior tranche LP requesting a redemption and being able to execute it
     */
    function __ERC4626_JT_Kernel_init_unchained(address _jtVault, address _jtAsset, uint256 _jtRedemptionDelaySeconds) internal onlyInitializing {
        // Ensure that the ST base asset is identical to the ERC4626 vault's base asset
        require(IERC4626(_jtVault).asset() == _jtAsset, TRANCHE_AND_VAULT_ASSET_MISMATCH());

        // Extend a one time max approval to the ERC4626 vault for the JT's base asset
        IERC20(_jtAsset).forceApprove(address(_jtVault), type(uint256).max);

        // Initialize the ERC4626 JT kernel storage
        ERC4626KernelStorageLib._getERC4626KernelStorage().jtVault = _jtVault;

        // Initialize the async redemption delay kernel state
        __RedemptionDelay_JT_Kernel_init_unchained(_jtRedemptionDelaySeconds);
    }

    /// @inheritdoc IRoycoKernel
    function jtPreviewDeposit(TRANCHE_UNIT _assets) external view override returns (NAV_UNIT valueAllocated, NAV_UNIT navToMintAt) {
        IERC4626 jtVault = IERC4626(ERC4626KernelStorageLib._getERC4626KernelStorage().jtVault);

        // Simulate the deposit of the assets into the underlying investment vault
        uint256 underlyingJTVaultSharesAllocated = jtVault.previewDeposit(toUint256(_assets));

        // Convert the underlying vault shares to tranche units. This value may differ from _assets if a fee or slippage is incurred to the deposit.
        TRANCHE_UNIT jtAssetsAllocated = toTrancheUnits(jtVault.convertToAssets(underlyingJTVaultSharesAllocated));

        // Convert the assets allocated to NAV units and preview a sync to get the current NAV to mint shares at for the junior tranche
        valueAllocated = jtConvertTrancheUnitsToNAVUnits(jtAssetsAllocated);
        navToMintAt = (_accountant().previewSyncTrancheAccounting(_getSeniorTrancheRawNAV(), _getJuniorTrancheRawNAV())).jtEffectiveNAV;
    }

    /// @inheritdoc IRoycoKernel
    function jtDeposit(
        TRANCHE_UNIT _assets,
        address,
        address
    )
        external
        override(IRoycoKernel)
        onlyJuniorTranche
        whenNotPaused
        returns (NAV_UNIT valueAllocated, NAV_UNIT navToMintAt)
    {
        // Execute a pre-op sync on accounting
        navToMintAt = (_preOpSyncTrancheAccounting()).jtEffectiveNAV;

        // Deposit the assets into the underlying investment vault and add to the number of ST controlled shares for this vault
        ERC4626KernelState storage $ = ERC4626KernelStorageLib._getERC4626KernelStorage();
        $.jtOwnedShares += IERC4626($.jtVault).deposit(toUint256(_assets), address(this));

        // Execute a post-op sync on accounting
        NAV_UNIT postDepositNAV = (_postOpSyncTrancheAccounting(Operation.JT_INCREASE_NAV)).jtEffectiveNAV;
        // The value allocated after any fees/slippage incurred on deposit
        valueAllocated = postDepositNAV - navToMintAt;
    }

    /// @inheritdoc IRoycoKernel
    function jtRedeem(
        uint256 _shares,
        address _controller,
        address _receiver
    )
        external
        override(IRoycoKernel)
        onlyJuniorTranche
        returns (AssetClaims memory userAssetClaims)
    {
        // Execute a pre-op sync on accounting
        SyncedAccountingState memory state;
        uint256 totalTrancheShares;
        (state, userAssetClaims, totalTrancheShares) = _preOpSyncTrancheAccounting(TrancheType.JUNIOR);

        // Ensure that the shares to redeem are actually claimable right now
        require(_shares <= _jtClaimableRedeemRequest(_controller), INSUFFICIENT_CLAIMABLE_SHARES(_shares, _jtClaimableRedeemRequest(_controller)));

        // Get the total NAV to withdraw on this redemption
        NAV_UNIT navOfSharesToRedeem = _processClaimableRedeemRequest(_controller, state.jtEffectiveNAV, _shares, totalTrancheShares);

        // Scale the claims based on the NAV to liquidate for the user relative to the total JT controlled NAV
        userAssetClaims = UtilsLib.scaleTrancheAssetsClaim(userAssetClaims, navOfSharesToRedeem, state.jtEffectiveNAV);

        // Withdraw the asset claims from each tranche and transfer them to the receiver
        _withdrawAssets(userAssetClaims, _receiver);

        // Execute a post-op sync on accounting and enforce the market's coverage requirement
        _postOpSyncTrancheAccountingAndEnforceCoverage(Operation.JT_DECREASE_NAV);
    }
}
