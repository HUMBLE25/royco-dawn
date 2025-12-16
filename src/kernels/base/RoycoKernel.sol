// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { RoycoBase } from "../../base/RoycoBase.sol";
import { IRoycoKernel } from "../../interfaces/kernel/IRoycoKernel.sol";
import { IRoycoVaultTranche } from "../../interfaces/tranche/IRoycoVaultTranche.sol";
import { ZERO_NAV_UNITS } from "../../libraries/Constants.sol";
import { RoycoKernelInitParams, RoycoKernelState, RoycoKernelStorageLib } from "../../libraries/RoycoKernelStorageLib.sol";
import { SyncedAccountingState, TrancheAssetClaims, TrancheType } from "../../libraries/Types.sol";
import { NAV_UNIT, TRANCHE_UNIT, UnitsMathLib } from "../../libraries/Units.sol";
import { Math } from "../../libraries/UtilsLib.sol";
import { IRoycoAccountant, Operation } from "./../../interfaces/IRoycoAccountant.sol";

/**
 * @title RoycoKernel
 * @notice Abstract contract for Royco kernel implementations
 * @dev Provides the foundational logic for kernel contracts including pre and post operation NAV reconciliation, coverage enforcement logic,
 *      and base wiring for tranche synchronization. All concrete kernel implementations should inherit from the Royco Kernel.
 */
abstract contract RoycoKernel is IRoycoKernel, RoycoBase {
    using UnitsMathLib for NAV_UNIT;
    using UnitsMathLib for TRANCHE_UNIT;
    using Math for uint256;

    /// @dev Permissions the function to only the market's senior tranche
    /// @dev Should be placed on all ST deposit and withdraw functions
    modifier onlySeniorTranche() {
        require(msg.sender == RoycoKernelStorageLib._getRoycoKernelStorage().seniorTranche, ONLY_SENIOR_TRANCHE());
        _;
    }

    /// @dev Permissions the function to only the market's junior tranche
    /// @dev Should be placed on all JT deposit and withdraw functions
    modifier onlyJuniorTranche() {
        require(msg.sender == RoycoKernelStorageLib._getRoycoKernelStorage().juniorTranche, ONLY_JUNIOR_TRANCHE());
        _;
    }

    /**
     * @notice Initializes the base kernel state
     * @dev Initializes any parent contracts and the base kernel state
     * @param _params The initialization parameters for the Royco kernel
     * @param _initialAuthority The initial authority for the base kernel
     */
    function __RoycoKernel_init(RoycoKernelInitParams memory _params, address _initialAuthority) internal onlyInitializing {
        __RoycoBase_init(_initialAuthority);
        __RoycoKernel_init_unchained(_params);
    }

    /**
     * @notice Initializes the base kernel state
     * @dev Checks the initial market's configuration and initializes the base kernel state
     * @param _params The initialization parameters for the base kernel
     */
    function __RoycoKernel_init_unchained(RoycoKernelInitParams memory _params) internal onlyInitializing {
        // Ensure that the tranche addresses, accountant, and protocol fee recipient are not null
        require(
            _params.seniorTranche != address(0) && _params.juniorTranche != address(0) && _params.accountant != address(0)
                && _params.protocolFeeRecipient != address(0),
            NULL_ADDRESS()
        );
        // Initialize the base kernel state
        RoycoKernelStorageLib.__RoycoKernel_init(_params);
    }

    /// @inheritdoc IRoycoKernel
    function stMaxDeposit(address _receiver) external view override(IRoycoKernel) returns (TRANCHE_UNIT) {
        NAV_UNIT stMaxDepositableNAV = _accountant().maxSTDepositGivenCoverage(_getSeniorTrancheRawNAV(), _getJuniorTrancheRawNAV());
        return Math.min(_maxSTDepositGlobally(_receiver), stConvertNAVUnitsToTrancheUnits(stMaxDepositableNAV));
    }

    /// @inheritdoc IRoycoKernel
    function stMaxWithdraw(address _owner) external view override(IRoycoKernel) returns (NAV_UNIT) {
        NAV_UNIT stEffectiveNAV = _accountant().previewSyncTrancheNAVs(_getSeniorTrancheRawNAV(), _getJuniorTrancheRawNAV()).stEffectiveNAV;
        // TODO: account for liq constraints
        return stEffectiveNAV;
    }

    /// @inheritdoc IRoycoKernel
    function jtMaxDeposit(address _receiver) external view override(IRoycoKernel) returns (TRANCHE_UNIT) {
        return _maxJTDepositGlobally(_receiver);
    }

    /// @inheritdoc IRoycoKernel
    function jtMaxWithdraw(address _owner) external view override(IRoycoKernel) returns (NAV_UNIT) {
        NAV_UNIT jtMaxWithdrawableNAV = _accountant().maxSTDepositGivenCoverage(_getSeniorTrancheRawNAV(), _getJuniorTrancheRawNAV());
        // TODO: account for liq constraints
        return jtMaxWithdrawableNAV;
    }

    /// @inheritdoc IRoycoKernel
    function getSTRawNAV() external view override(IRoycoKernel) returns (uint256) {
        return _getSeniorTrancheRawNAV();
    }

    /// @inheritdoc IRoycoKernel
    function getJTRawNAV() external view override(IRoycoKernel) returns (uint256) {
        return _getJuniorTrancheRawNAV();
    }

    /// @inheritdoc IRoycoKernel
    function getState() external view override(IRoycoKernel) returns (RoycoKernelState memory) {
        return RoycoKernelStorageLib._getRoycoKernelStorage();
    }

    /**
     * @notice Synchronizes and persists the raw and effective NAVs of both tranches
     * @dev Only executes a pre-op sync because there is no operation being executed in the same call as this sync
     * @return state The synced NAV, debt, and fee accounting containing all mark to market accounting data
     * @return state The synced NAV, debt, and fee accounting containing all mark to market accounting data
     */
    function syncTrancheNAVs() external override(IRoycoKernel) restricted returns (SyncedAccountingState memory state, TrancheAssetClaims memory claims) {
        return _preOpSyncTrancheNAVs();
    }

    /**
     * @notice Previews a synchronization of the raw and effective NAVs of both tranches
     * @dev Does not mutate any state
     * @param _trancheType An enum representing which tranche to execute this preview for
     * @return state The synced NAV, debt, and fee accounting containing all mark to market accounting data
     */
    function previewSyncTrancheNAVs(TrancheType _trancheType)
        public
        view
        override(IRoycoKernel)
        returns (SyncedAccountingState memory state, TrancheAssetClaims memory claims)
    {
        state = _accountant().previewSyncTrancheNAVs(_getSeniorTrancheRawNAV(), _getJuniorTrancheRawNAV());

        (NAV_UNIT stSelfNAVClaim, NAV_UNIT stNAVClaimOnJT, NAV_UNIT jtSelfNAVClaim, NAV_UNIT jtNAVClaimOnST) = _decomposeNAVClaims(state);

        if (_trancheType == TrancheType.SENIOR) {
            if (stSelfNAVClaim != ZERO_NAV_UNITS) claims.stAssets = stConvertNAVUnitsToTrancheUnits(stSelfNAVClaim);
            if (stNAVClaimOnJT != ZERO_NAV_UNITS) claims.jtAssets = jtConvertNAVUnitsToTrancheUnits(stNAVClaimOnJT);
        } else {
            if (jtNAVClaimOnST != ZERO_NAV_UNITS) claims.stAssets = stConvertNAVUnitsToTrancheUnits(jtNAVClaimOnST);
            if (jtSelfNAVClaim != ZERO_NAV_UNITS) claims.jtAssets = jtConvertNAVUnitsToTrancheUnits(jtSelfNAVClaim);
        }
    }

    /**
     * @notice Invokes the accountant to do a pre-operation (deposit and withdrawal) NAV sync
     * @dev Should be called on every NAV mutating user operation
     * @return state The synced NAV, debt, and fee accounting containing all mark to market accounting data
     */
    function _preOpSyncTrancheNAVs() internal returns (SyncedAccountingState memory state) {
        // Execute the pre-op sync via the accountant
        state = _accountant().preOpSyncTrancheNAVs(_getSeniorTrancheRawNAV(), _getJuniorTrancheRawNAV());

        // Collect any protocol fees accrued from the sync to the fee recipient
        if (state.stProtocolFeeAccrued != 0 || state.jtProtocolFeeAccrued != 0) {
            RoycoKernelState storage $ = RoycoKernelStorageLib._getRoycoKernelStorage();
            address protocolFeeRecipient = $.protocolFeeRecipient;
            // If ST yield was distributed, Mint ST protocol fee shares to the protocol fee recipient
            if (state.stProtocolFeeAccrued != 0) {
                IRoycoVaultTranche($.seniorTranche).mintProtocolFeeShares(state.stProtocolFeeAccrued, state.stEffectiveNAV, protocolFeeRecipient);
            }
            // If JT yield was distributed, Mint JT protocol fee shares to the protocol fee recipient
            if (state.jtProtocolFeeAccrued != 0) {
                IRoycoVaultTranche($.juniorTranche).mintProtocolFeeShares(state.jtProtocolFeeAccrued, state.jtEffectiveNAV, protocolFeeRecipient);
            }
        }
    }

    /**
     * @notice Invokes the accountant to do a post-operation (deposit and withdrawal) NAV sync
     * @dev Should be called on every NAV mutating user operation that doesn't require a coverage check
     * @param _op The operation being executed in between the pre and post synchronizations
     */
    function _postOpSyncTrancheNAVs(Operation _op) internal {
        // Execute the post-op sync on the accountant
        _accountant().postOpSyncTrancheNAVs(_getSeniorTrancheRawNAV(), _getJuniorTrancheRawNAV(), _op);
    }

    /**
     * @notice Invokes the accountant to do a post-operation (deposit and withdrawal) NAV sync and checks the market's coverage requirement is satisfied
     * @dev Should be called on every NAV mutating user operation that requires a coverage check: ST deposit and JT withdrawal
     * @param _op The operation being executed in between the pre and post synchronizations
     */
    function _postOpSyncTrancheNAVsAndEnforceCoverage(Operation _op) internal {
        // Execute the post-op sync on the accountant
        _accountant().postOpSyncTrancheNAVsAndEnforceCoverage(_getSeniorTrancheRawNAV(), _getJuniorTrancheRawNAV(), _op);
    }

    /**
     * @notice Decomposes effective NAVs into self-backed NAV claims and cross-tranche NAV claims
     * @param _state The synced NAV, debt, and fee accounting containing all mark to market accounting data
     * @return stSelfNAVClaim The portion of ST's effective NAV that must be funded by ST’s raw NAV
     * @return stNAVClaimOnJT The portion of ST's effective NAV that must be funded by JT’s raw NAV
     * @return jtSelfNAVClaim The portion of JT's effective NAV that must be funded by JT’s raw NAV
     * @return jtNAVClaimOnST The portion of JT's effective NAV that must be funded by ST’s raw NAV
     */
    function _decomposeNAVClaims(SyncedAccountingState memory _state)
        internal
        pure
        returns (NAV_UNIT stSelfNAVClaim, NAV_UNIT stNAVClaimOnJT, NAV_UNIT jtSelfNAVClaim, NAV_UNIT jtNAVClaimOnST)
    {
        // Cross-tranche claims (only one direction should be non-zero under conservation)
        stNAVClaimOnJT = UnitsMathLib.saturatingSub(_state.stEffectiveNAV, _state.stRawNAV);
        jtNAVClaimOnST = UnitsMathLib.saturatingSub(_state.jtEffectiveNAV, _state.jtRawNAV);

        // Self-backed portions (the remainder of each tranche’s effective NAV)
        stSelfNAVClaim = UnitsMathLib.saturatingSub(_state.stRawNAV, jtNAVClaimOnST);
        jtSelfNAVClaim = UnitsMathLib.saturatingSub(_state.jtRawNAV, stNAVClaimOnJT);
    }

    /// @notice Returns this kernel's accountant casted to the IRoycoAccountant interface
    /// @return The Royco Accountant for this kernel
    function _accountant() internal view returns (IRoycoAccountant) {
        return IRoycoAccountant(RoycoKernelStorageLib._getRoycoKernelStorage().accountant);
    }

    /// @notice Returns the raw net asset value of the senior tranche denominated in the NAV units (USD, BTC, etc.) for this kernel
    /// @return The pure net asset value of the senior tranche invested assets
    function _getSeniorTrancheRawNAV() internal view virtual returns (NAV_UNIT);

    /// @notice Returns the raw net asset value of the junior tranche denominated in the NAV units (USD, BTC, etc.) for this kernel
    /// @return The pure net asset value of the junior tranche invested assets
    function _getJuniorTrancheRawNAV() internal view virtual returns (NAV_UNIT);

    /**
     * @notice Returns the maximum amount of assets that can be deposited into the senior tranche globally
     * @dev Implementation should consider protocol-wide limits and liquidity constraints
     * @param _receiver The receiver of the shares for the assets being deposited (used to enforce white/black lists)
     */
    function _maxSTDepositGlobally(address _receiver) internal view virtual returns (TRANCHE_UNIT);

    /**
     * @notice Returns the maximum amount of assets that can be deposited into the junior tranche globally
     * @dev Implementation should consider protocol-wide limits and liquidity constraints
     * @param _receiver The receiver of the shares for the assets being deposited (used to enforce white/black lists)
     */
    function _maxJTDepositGlobally(address _receiver) internal view virtual returns (TRANCHE_UNIT);

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn from the senior tranche globally
     * @dev Implementation should consider protocol-wide limits and liquidity constraints
     * @param _owner The owner of the assets being withdrawn (used to enforce white/black lists)
     */
    function _maxSTWithdrawalGlobally(address _owner) internal view virtual returns (TRANCHE_UNIT);

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn from the junior tranche globally
     * @dev Implementation should consider protocol-wide limits and liquidity constraints
     * @param _owner The owner of the assets being withdrawn (used to enforce white/black lists)
     */
    function _maxJTWithdrawalGlobally(address _owner) internal view virtual returns (TRANCHE_UNIT);

    /**
     * @notice Covers senior tranche losses from the junior tranche's controlled assets
     * @param _asset The asset to cover losses in
     * @param _nav The NAV to claim from JT to ST
     * @param _receiver The receiver of the assets
     */
    function _claimSeniorNAVFromJunior(address _asset, NAV_UNIT _nav, address _receiver) internal virtual;

    /**
     * @notice Claims junior tranche yield and debt repayment from the senior tranche's controlled assets
     * @param _asset The asset to claim yield and debt repayment in
     * @param _nav The NAV to claim from S to ST
     * @param _receiver The receiver of the assets
     */
    function _claimJuniorNAVFromSenior(address _asset, NAV_UNIT _nav, address _receiver) internal virtual;
}
