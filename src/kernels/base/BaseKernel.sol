// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "../../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "../../../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import { RoycoAuth, RoycoRoles } from "../../auth/RoycoAuth.sol";
import { IRDM } from "../../interfaces/IRDM.sol";
import { IBaseKernel } from "../../interfaces/kernel/IBaseKernel.sol";
import { BaseKernelInitParams, BaseKernelState, BaseKernelStorageLib, Operation } from "../../libraries/BaseKernelStorageLib.sol";
import { ConstantsLib, Math, UtilsLib } from "../../libraries/UtilsLib.sol";

/**
 * @title BaseKernel
 * @notice Base abstract contract for kernel implementations that provides delegate call protection
 * @dev Provides the foundational functionality for kernel contracts including delegatecall enforcement
 * @dev All kernel contracts should inherit from this base contract to ensure proper execution context
 *      and use the modifier as stipulated by the IBaseKernel interface.
 */
abstract contract BaseKernel is Initializable, IBaseKernel, UUPSUpgradeable, RoycoAuth {
    using Math for uint256;

    /// @notice Thrown when the market's coverage requirement is unsatisfied
    error INSUFFICIENT_COVERAGE();

    /// @notice Thrown when the caller of a permissioned function isn't the market's senior tranche
    error ONLY_SENIOR_TRANCHE();

    /// @notice Thrown when the caller of a permissioned function isn't the market's junior tranche
    error ONLY_JUNIOR_TRANCHE();

    /// @notice Thrown when an operation results in an invalid NAV state in the post-operation synchronization
    error INVALID_POST_OP_STATE(Operation _op);

    /// @dev Permissions the function to only the market's senior tranche
    /// @dev Should be placed on all ST deposit and withdraw functions
    modifier onlySeniorTranche() {
        _onlySeniorTranche();
        _;
    }

    function _onlySeniorTranche() internal view {
        require(msg.sender == BaseKernelStorageLib._getBaseKernelStorage().seniorTranche, ONLY_SENIOR_TRANCHE());
    }

    /// @dev Permissions the function to only the market's junior tranche
    /// @dev Should be placed on all JT deposit and withdraw functions
    modifier onlyJuniorTranche() {
        _onlyJuniorTranche();
        _;
    }

    function _onlyJuniorTranche() internal view {
        require(msg.sender == BaseKernelStorageLib._getBaseKernelStorage().juniorTranche, ONLY_JUNIOR_TRANCHE());
    }

    /**
     * @notice Synchronizes tranche NAVs before and after an operation (deposit or withdrawal).
     * @dev Should be placed on senior tranche withdrawal functions and junior tranche deposit functions since coverage doesn't need to be enforced
     * @dev Before execution: realizes unrealized PnL into effective NAVs
     * @dev After execution: applies the effects of the operation (deposit or withdrawal) to all NAVs
     * @param _op The operation being executed in between the pre and post synchronizations
     */
    modifier syncNAVs(Operation _op) {
        // Sync the tranche NAVs based on the difference in current NAVs and checkpointed NAVs since the last operation
        // Any NAV updates caused by this are a result of unrealized PNL(s) in the underlying strategy
        _preOpSyncTrancheNAVs();
        _;
        // Sync the NAVs after the operation (deposit or withdrawal) has been executed
        // Any NAV updates caused by this are a result of a deposit or withdrawal
        _postOpSyncTrancheNAVs(_op);
    }

    /**
     * @notice Synchronizes tranche NAVs before and after an operation (deposit or withdrawal).
     * @dev Should be placed on senior tranche deposit functions and junior tranche withdrawal functions since coverage needs to be enforced
     * @dev Before execution: realizes unrealized PnL into effective NAVs
     * @dev After execution: applies the effects of the operation (deposit or withdrawal) to all NAVs
     * @param _op The operation being executed in between the pre and post synchronizations
     */
    modifier syncNAVsAndEnforceCoverage(Operation _op) {
        // Sync the tranche NAVs based on the difference in current NAVs and checkpointed NAVs since the last operation
        // Any NAV updates caused by this are a result of unrealized PNL(s) in the underlying strategy
        _preOpSyncTrancheNAVs();
        _;
        // Sync the NAVs after the operation (deposit or withdrawal) has been executed
        // Any NAV updates caused by this are a result of a deposit or withdrawal
        _postOpSyncTrancheNAVs(_op);
        // Enforce that the coverage requirement of the market is satisfied
        _enforceCoverage();
    }

    /**
     * @notice Initializes the base kernel state
     * @dev Initializes any parent contracts and the base kernel state
     * @param _params The initialization parameters for the base kernel
     * @param _owner The initial owner of the base kernel
     * @param _pauser The initial pauser of the base kernel
     */
    function __BaseKernel_init(BaseKernelInitParams memory _params, address _owner, address _pauser) internal onlyInitializing {
        // Initialize the auth state of the kernel
        __RoycoAuth_init(_owner, _pauser);
        // Initialize the base kernel state
        __BaseKernel_init_unchained(_params);
    }

    /**
     * @notice Initializes the base kernel state
     * @dev Checks the initial market's configuration and initializes the base kernel state
     * @param _params The initialization parameters for the base kernel
     */
    function __BaseKernel_init_unchained(BaseKernelInitParams memory _params) internal onlyInitializing {
        // Ensure that the coverage requirement is valid
        require(_params.coverageWAD < ConstantsLib.WAD && _params.coverageWAD >= ConstantsLib.MIN_COVERAGE_WAD);
        // Ensure that JT withdrawals are not permanently bricked
        require(uint256(_params.coverageWAD).mulDiv(_params.betaWAD, ConstantsLib.WAD, Math.Rounding.Ceil) < ConstantsLib.WAD);
        // Ensure that the tranche address and RDM are not null
        require((bytes20(_params.seniorTranche) & bytes20(_params.juniorTranche) & bytes20(_params.rdm)) != bytes20(0));
        // Initialize the base kernel state
        BaseKernelStorageLib.__BaseKernel_init(_params);
    }

    /// @inheritdoc IBaseKernel
    function stMaxDeposit(address, address _receiver) external view override(IBaseKernel) returns (uint256) {
        return Math.min(_maxSTDepositGlobally(_receiver), _maxSTDepositGivenCoverage());
    }

    /// @inheritdoc IBaseKernel
    function stMaxWithdraw(address, address _owner) external view override(IBaseKernel) returns (uint256) {
        return _maxSTWithdrawalGlobally(_owner);
    }

    /// @inheritdoc IBaseKernel
    function jtMaxDeposit(address, address _receiver) external view override(IBaseKernel) returns (uint256) {
        return _maxJTDepositGlobally(_receiver);
    }

    /// @inheritdoc IBaseKernel
    function jtMaxWithdraw(address, address _owner) external view override(IBaseKernel) returns (uint256) {
        return Math.min(_maxJTWithdrawalGlobally(_owner), _maxJTWithdrawalGivenCoverage());
    }

    /// @inheritdoc IBaseKernel
    function getSTRawNAV() external view override(IBaseKernel) returns (uint256) {
        return _getSeniorTrancheRawNAV();
    }

    /// @inheritdoc IBaseKernel
    function getJTRawNAV() external view override(IBaseKernel) returns (uint256) {
        return _getJuniorTrancheRawNAV();
    }

    /// @inheritdoc IBaseKernel
    function getSTEffectiveNAV() external view override(IBaseKernel) returns (uint256) {
        return _getSeniorTrancheEffectiveNAV();
    }

    /// @inheritdoc IBaseKernel
    function getJTEffectiveNAV() external view override(IBaseKernel) returns (uint256) {
        return _getJuniorTrancheEffectiveNAV();
    }

    /**
     * @notice Synchronizes the raw and effective NAVs of both tranches
     * @dev Only performs a pre-op sync because there is no operation being executed in the same function call as this sync
     * @return stRawNAV The senior tranche's raw NAV: the pure value of its investment
     * @return jtRawNAV The junior tranche's raw NAV: the pure value of its investment
     * @return stEffectiveNAV The senior tranche's effective NAV, including applied coverage, ST yield distribution, and uncovered losses
     * @return jtEffectiveNAV The junior tranche's effective NAV, including provided coverage, JT yield, ST yield distribution, and JT losses
     */
    function syncTrancheNAVs()
        external
        onlyRole(RoycoRoles.SYNC_ROLE)
        whenNotPaused
        returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV)
    {
        return _preOpSyncTrancheNAVs();
    }

    /**
     * @notice Synchronizes the raw and effective NAVs of both tranches before any operation
     * @dev Accrues JT yield share over time based on the market's RDM output
     * @dev Applies unrealized PnL and yield distribution
     * @dev Persists updated NAV checkpoints for the next sync to use as reference
     * @return stRawNAV The senior tranche's raw NAV: the pure value of its investment
     * @return jtRawNAV The junior tranche's raw NAV: the pure value of its investment
     * @return stEffectiveNAV The senior tranche's effective NAV, including applied coverage, ST yield distribution, and uncovered losses
     * @return jtEffectiveNAV The junior tranche's effective NAV, including provided coverage, JT yield, ST yield distribution, and JT losses
     */
    function _preOpSyncTrancheNAVs() internal returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV) {
        // Get the storage pointer to the base kernel state
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();

        // Accrue the yield distribution owed to JT since the last tranche interaction
        uint256 twJTYieldShareAccruedWAD = $.twJTYieldShareAccruedWAD = _previewJTYieldShareAccrual();
        $.lastAccrualTimestamp = uint32(block.timestamp);

        // Preview the raw and coverage adjusted (effective) NAVs of each tranche
        bool yieldDistributed;
        uint256 stCoverageDebt;
        uint256 jtCoverageDebt;
        (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV, stCoverageDebt, jtCoverageDebt, yieldDistributed) = _previewEffectiveNAVs(twJTYieldShareAccruedWAD);
        // If yield was distributed, reset the accumulator and update the last yield distribution timestamp
        if (yieldDistributed) {
            delete $.twJTYieldShareAccruedWAD;
            $.lastDistributionTimestamp = uint32(block.timestamp);
        }

        // Checkpoint the computed NAVs
        $.lastSTRawNAV = stRawNAV;
        $.lastJTRawNAV = jtRawNAV;
        $.lastSTEffectiveNAV = stEffectiveNAV;
        $.lastJTEffectiveNAV = jtEffectiveNAV;
        $.lastSTCoverageDebt = stCoverageDebt;
        $.lastJTCoverageDebt = jtCoverageDebt;
    }

    /**
     * @notice Previews the current raw and effective NAVs of each tranche
     * @dev Computes PnL deltas in raw NAVs since the last sync and applies JT PnL, ST losses with applicable JT coverage, and ST yield distribution
     * @param _twJTYieldShareAccruedWAD The accumulated time-weighted JT yield share since the last yield distribution
     * @return stRawNAV The senior tranche's raw NAV: the pure value of its investment
     * @return jtRawNAV The junior tranche's raw NAV: the pure value of its investment
     * @return stEffectiveNAV The senior tranche's effective NAV, including applied coverage, ST yield distribution, and uncovered losses
     * @return jtEffectiveNAV The junior tranche's effective NAV, including provided coverage, JT yield, ST yield distribution, and JT losses
     * @return stCoverageDebt The total coverage that has been applied to ST from the JT loss-absorption buffer : represents a claim the junior tranche has on future senior-side recoveries
     * @return jtCoverageDebt The total losses that ST incurred after exhausting the JT loss-absorption buffer: represents a claim the senior tranche has on future junior-side recoveries
     * @return yieldDistributed Boolean indicating whether the ST accrued yield and it was distributed between ST and JT
     */
    function _previewEffectiveNAVs(uint256 _twJTYieldShareAccruedWAD)
        internal
        view
        returns (
            uint256 stRawNAV,
            uint256 jtRawNAV,
            uint256 stEffectiveNAV,
            uint256 jtEffectiveNAV,
            uint256 stCoverageDebt,
            uint256 jtCoverageDebt,
            bool yieldDistributed
        )
    {
        // Get the storage pointer to the base kernel state
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();

        // Compute the delta in the raw NAV of the junior tranche
        // The delta represents the unrealized JT PNL of the underlying investment since the last NAV checkpoints
        jtRawNAV = _getJuniorTrancheRawNAV();
        int256 deltaJT = _computeRawNAVDelta(jtRawNAV, $.lastJTRawNAV);

        // Cache the last checkpointed effective NAV and coverage debt for each tranche
        stEffectiveNAV = $.lastSTEffectiveNAV;
        jtEffectiveNAV = $.lastJTEffectiveNAV;
        stCoverageDebt = $.lastSTCoverageDebt;
        jtCoverageDebt = $.lastJTCoverageDebt;

        /// @dev STEP_JT_APPLY_LOSS: The JT assets depreciated in value
        if (deltaJT < 0) {
            // JT incurs as much of the loss as possible, booking the remainder as a future liability to ST
            uint256 jtLoss = uint256(-deltaJT);
            uint256 jtAbsorbableLoss = Math.min(jtLoss, jtEffectiveNAV);
            /// @dev STEP_JT_LOSS_OVERFLOW_TO_ST: This loss isn't fully absorbable by JT's remaning loss-absorption buffer
            if (jtLoss > jtAbsorbableLoss) {
                // The excess loss is absorbed by ST
                uint256 stLoss = jtLoss - jtEffectiveNAV;
                stEffectiveNAV -= stLoss;
                // Repay ST debt to JT
                // This is equivalent to retroactively removing coverage for previously covered losses
                // Thus, the liability is flipped to JT debt to ST
                stCoverageDebt -= stLoss;
                jtCoverageDebt += stLoss;
            }
            /// @dev STEP_JT_ABSORB_LOSS: This loss is fully absorbable by JT's remaning loss-absorption buffer
            jtEffectiveNAV -= jtAbsorbableLoss;
            /// @dev STEP_JT_APPLY_GAIN: The JT assets appreciated in value
        } else if (deltaJT > 0) {
            uint256 jtGain = uint256(deltaJT);
            /// @dev STEP_REPAY_JT_COVERAGE_DEBT: Pay off any JT debt to ST (previously uncovered losses)
            uint256 jtDebtRepayment = Math.min(jtGain, jtCoverageDebt);
            if (jtDebtRepayment != 0) {
                // Repay JT debt to ST
                // This is equivalent to retroactively applying coverage for previously uncovered losses
                // Thus, the liability is flipped to ST debt to JT
                jtCoverageDebt -= jtDebtRepayment;
                stCoverageDebt += jtDebtRepayment;
                // Apply the repayment (retroactive coverage) to the ST
                stEffectiveNAV += jtDebtRepayment;
                jtGain -= jtDebtRepayment;
            }
            /// @dev STEP_JT_BOOK_REMAINING_GAIN: JT accrues remaining appreciation
            jtEffectiveNAV += jtGain;
        }

        // Compute the delta in the raw NAV of the senior tranche
        // The delta represents the unrealized ST PNL of the underlying investment since the last NAV checkpoints
        stRawNAV = _getSeniorTrancheRawNAV();
        int256 deltaST = _computeRawNAVDelta(stRawNAV, $.lastSTRawNAV);

        /// @dev STEP_ST_NO_CHANGE: The ST assets experienced no change in value
        if (deltaST == 0) {
            return (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV, stCoverageDebt, jtCoverageDebt, false);
            /// @dev STEP_ST_APPLY_LOSS: The ST assets depreciated in value
        } else if (deltaST < 0) {
            uint256 stLoss = uint256(-deltaST);
            /// @dev STEP_APPLY_JT_COVERAGE_TO_ST: Apply any possible coverage to ST provided by JT's loss-absorption buffer
            uint256 coverageApplied = Math.min(stLoss, jtEffectiveNAV);
            if (coverageApplied != 0) {
                jtEffectiveNAV -= coverageApplied;
                // Any coverage provided is a ST liability to JT
                stCoverageDebt += coverageApplied;
            }
            /// @dev STEP_ST_INCURS_RESIDUAL_LOSSES: Apply any uncovered losses by JT to ST
            uint256 netStLoss = stLoss - coverageApplied;
            if (netStLoss != 0) {
                stEffectiveNAV -= netStLoss;
                // The uncovered portion of the ST loss is a JT liability to ST
                jtCoverageDebt += netStLoss;
            }
            /// @dev STEP_ST_APPLY_GAIN: The ST assets appreciated in value
        } else {
            uint256 stGain = uint256(deltaST);
            /// @dev STEP_REPAY_JT_COVERAGE_DEBT: The first priority of repayment to reverse the loss-waterfall is making ST whole again
            // Repay JT debt to ST: previously uncovered ST losses
            uint256 debtRepayment = Math.min(stGain, jtCoverageDebt);
            if (debtRepayment != 0) {
                // Pay back debt to ST
                stEffectiveNAV += debtRepayment;
                jtCoverageDebt -= debtRepayment;
                // Deduct the repayment from the ST gains and return if no gains are left
                stGain -= debtRepayment;
                if (stGain == 0) return (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV, stCoverageDebt, jtCoverageDebt, false);
            }

            /// @dev STEP_REPAY_ST_COVERAGE_DEBT: The second priority of repayment to reverse the loss-waterfall is making JT whole again
            // Repay ST debt to JT: previously applied coverage from JT to ST
            debtRepayment = Math.min(stGain, stCoverageDebt);
            if (debtRepayment != 0) {
                // Pay back debt to JT
                jtEffectiveNAV += debtRepayment;
                stCoverageDebt -= debtRepayment;
                // Deduct the repayment from the remaining ST gains and return if no gains are left
                stGain -= debtRepayment;
                if (stGain == 0) return (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV, stCoverageDebt, jtCoverageDebt, false);
            }

            /// @dev STEP_DISTRIBUTE_YIELD: There are no remaining debts in the system and the residual gains can be used to distribute yield to both tranches
            // Compute the time weighted average JT share of yield
            uint256 elapsed = block.timestamp - $.lastDistributionTimestamp;
            // Preemptively accrue all yield to ST and return if last yield distribution was in the same block
            // No need to update yield share accumulator and timestamp so return false for yieldDistributed
            if (elapsed == 0) return (stRawNAV, jtRawNAV, (stEffectiveNAV + stGain), jtEffectiveNAV, stCoverageDebt, jtCoverageDebt, false);
            // Compute the time weighted JT yield share of this distribution scaled by WAD
            uint256 jtYieldShareWAD = _twJTYieldShareAccruedWAD / elapsed;
            // Round in favor of the senior tranche
            uint256 jtYield = stGain.mulDiv(jtYieldShareWAD, ConstantsLib.WAD, Math.Rounding.Floor);
            // Apply the yield split: adding each tranche's share of earnings to their effective NAVs
            jtEffectiveNAV += jtYield;
            stEffectiveNAV += (stGain - jtYield);
            yieldDistributed = true;
        }
    }

    /**
     * @notice Computes the currently accrued JT yield share since the last yield distribution
     * @dev Gets the instantaneous JT yield share and accumulates it over the time elapsed since the last accrual
     * @return The updated time-weighted JT yield share since the last yield distribution
     */
    function _previewJTYieldShareAccrual() internal view returns (uint192) {
        // Get the storage pointer to the base kernel state
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();

        // Get the last update timestamp
        uint256 lastUpdate = $.lastAccrualTimestamp;
        if (lastUpdate == 0) return 0;

        // Compute the elapsed time since the last update
        uint256 elapsed = block.timestamp - lastUpdate;
        // Preemptively return if last accrual was in the same block
        if (elapsed == 0) return $.twJTYieldShareAccruedWAD;

        // Get the instantaneous JT yield share, scaled by WAD
        uint256 jtYieldShareWAD = IRDM($.rdm).getJTYieldShare($.lastSTRawNAV, $.lastJTRawNAV, $.betaWAD, $.coverageWAD, $.lastJTEffectiveNAV);
        // Apply the accural of JT yield share to the accumulator, weighted by the time elapsed
        return ($.twJTYieldShareAccruedWAD + uint192(jtYieldShareWAD * elapsed));
    }

    /**
     * @notice Applies post-operation (deposit and withdrawal) raw NAV deltas to effective NAV checkpoints
     * @dev Interprets deltas strictly as deposits/withdrawals with no yield or coverage logic
     * @param _op The operation being executed in between the pre and post synchronizations
     */
    function _postOpSyncTrancheNAVs(Operation _op) internal {
        // Get the storage pointer to the base kernel state
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();
        if (_op == Operation.ST_DEPOSIT) {
            // Compute the delta in the raw NAV of the senior tranche
            // The deltas represent the NAV changes after a deposit and withdrawal
            uint256 stRawNAV = _getSeniorTrancheRawNAV();
            int256 deltaST = _computeRawNAVDelta(stRawNAV, $.lastSTRawNAV);
            // Deposits must increase NAV
            require(deltaST > 0, INVALID_POST_OP_STATE(_op));
            // Update the post-operation raw NAV ST checkpoint
            $.lastSTRawNAV = stRawNAV;
            // Apply the deposit to the senior tranche's effective NAV
            $.lastSTEffectiveNAV += uint256(deltaST);
        } else if (_op == Operation.JT_DEPOSIT) {
            // Compute the delta in the raw NAV of the junior tranche
            // The deltas represent the NAV changes after a deposit and withdrawal
            uint256 jtRawNAV = _getJuniorTrancheRawNAV();
            int256 deltaJT = _computeRawNAVDelta(jtRawNAV, $.lastJTRawNAV);
            // Deposits must increase NAV
            require(deltaJT > 0, INVALID_POST_OP_STATE(_op));
            // Update the post-operation raw NAV ST checkpoint
            $.lastJTRawNAV = jtRawNAV;
            // Apply the deposit to the junior tranche's effective NAV
            $.lastJTEffectiveNAV += uint256(deltaJT);
        } else {
            // Compute the deltas in the raw NAVs of each tranche after an operation's execution and cache the raw NAVs
            // The deltas represent the NAV changes after a deposit and withdrawal
            uint256 stRawNAV = _getSeniorTrancheRawNAV();
            uint256 jtRawNAV = _getJuniorTrancheRawNAV();
            int256 deltaST = _computeRawNAVDelta(stRawNAV, $.lastSTRawNAV);
            int256 deltaJT = _computeRawNAVDelta(jtRawNAV, $.lastJTRawNAV);

            // Update the post-operation raw NAV checkpoints
            $.lastSTRawNAV = stRawNAV;
            $.lastJTRawNAV = jtRawNAV;

            if (_op == Operation.ST_WITHDRAW) {
                // ST withdrawals must decrease ST NAV and leave JT NAV decreased or unchanged (coverage realization)
                // Or they must leave ST NAV unchanged and decrease JT NAV (pure coverage realization)
                require((deltaST < 0 && deltaJT <= 0) || (deltaST == 0 && deltaJT < 0), INVALID_POST_OP_STATE(_op));
                // Senior withdrew: The NAV deltas include the discrete withdrawal amount in addition to any coverage pulled from JT to ST
                // If the withdrawal used JT capital as coverage to facilitate this ST withdrawal
                if (deltaJT < 0) {
                    // The actual amount withdrawn was the delta in ST raw NAV and the coverage applied from JT
                    uint256 coverageRealized = uint256(-deltaJT);
                    $.lastSTEffectiveNAV -= (uint256(-deltaST) + coverageRealized);
                    /// We need to adjust debts by accounting for the realized coverage
                    // The coverage realization waterfall works by first erasing ST debt and then JT debt
                    // This mimics the same top -> down waterfall used to apply coverage when computing effective NAVs
                    // Erase as much ST coverage debt as possible
                    uint256 stCoverageDebtErased = Math.min(coverageRealized, $.lastSTCoverageDebt);
                    if (stCoverageDebtErased != 0) $.lastSTCoverageDebt -= stCoverageDebtErased;
                    // Reduce remaining available coverage
                    coverageRealized -= stCoverageDebtErased;
                    // Apply the remainder to erasing JT debt
                    if (coverageRealized != 0) $.lastJTCoverageDebt = Math.saturatingSub($.lastJTCoverageDebt, coverageRealized);
                } else {
                    // Apply the withdrawal to the senior tranche's effective NAV
                    $.lastSTEffectiveNAV = Math.saturatingSub($.lastSTEffectiveNAV, uint256(-deltaST));
                }
            } else if (_op == Operation.JT_WITHDRAW) {
                // JT withdrawals must decrease JT NAV and leave ST NAV decreased or unchanged (yield claiming)
                require(deltaJT < 0 && deltaST <= 0, INVALID_POST_OP_STATE(_op));
                // Junior withdrew: The NAV deltas include the discrete withdrawal amount in addition to any yield pulled from ST to JT
                // If the withdrawal used ST capital to claim yield when facilitating this JT withdrawal
                // No need to touch debt accounting: all debts are cleared
                // If ST delta was negative, the actual amount withdrawn by JT was the delta in JT raw NAV and the yield claimed from ST
                if (deltaST < 0) $.lastJTEffectiveNAV = Math.saturatingSub($.lastJTEffectiveNAV, (uint256(-deltaJT) + uint256(-deltaST)));
                // Apply the pure withdrawal to the junior tranche's effective NAV
                else $.lastJTEffectiveNAV = Math.saturatingSub($.lastJTEffectiveNAV, uint256(-deltaJT));
            }
        }
    }

    /**
     * @notice Enforces the market’s coverage requirement
     * @dev Junior capital must be sufficient to absorb losses to the senior exposure up to the coverage ratio
     * @dev Must be used as a post-check after all NAVs have been synchronized
     * @dev Informally: junior loss absorbtion buffer >= total covered exposure
     * @dev Formally: JT_EFFECTIVE_NAV >= (ST_RAW_NAV + (JT_RAW_NAV * BETA_%)) * COV_%
     *      JT_EFFECTIVE_NAV is JT's current loss absorbtion buffer after applying all prior JT yield accrual and coverage adjustments
     *      ST_RAW_NAV and JT_RAW_NAV are the mark-to-market NAVs of the tranches
     *      BETA_% is the JT's sensitivity to the same downside stress that affects ST (eg. 0 if JT is in RFR and 1 if JT and ST are in the same opportunity)
     * @dev If we rearrange the coverage condition, we get:
     *      1 >= ((ST_RAW_NAV + (JT_RAW_NAV * BETA_%)) * COV_%) / JT_EFFECTIVE_NAV
     *      Notice that the RHS is identical to how we define utilization: 1 >= Utilization
     * @dev If this condition is unsatisfied, senior deposits and junior withdrawals must be blocked to prevent undercollateralized senior exposure
     * @dev Reverts if the condition is unsatisfied
     */
    function _enforceCoverage() internal view {
        // Get the storage pointer to the base kernel state
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();
        // Compute the utilization and enforce that the senior tranche is properly collateralized
        uint256 utilization = UtilsLib.computeUtilization($.lastSTRawNAV, $.lastJTRawNAV, $.betaWAD, $.coverageWAD, $.lastJTEffectiveNAV);
        require(ConstantsLib.WAD >= utilization, INSUFFICIENT_COVERAGE());
    }

    /**
     * @notice Returns the max assets depositable into the senior tranche without violating the market's coverage requirement
     * @dev Always rounds in favor of senior tranche protection
     * @dev Coverage Invariant: JT_EFFECTIVE_NAV >= (ST_RAW_NAV + (JT_RAW_NAV * BETA_%)) * COV_%
     * @dev Max assets depositable into ST, x: JT_EFFECTIVE_NAV = ((ST_RAW_NAV + x) + (JT_RAW_NAV * BETA_%)) * COV_%
     *      Isolate x: x = (JT_EFFECTIVE_NAV / COV_%) - (JT_RAW_NAV * BETA_%) - ST_RAW_NAV
     */
    function _maxSTDepositGivenCoverage() internal view returns (uint256) {
        // Get the storage pointer to the base kernel state
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();
        // Solve for x, rounding in favor of senior protection
        // Compute the total covered assets by the junior tranche loss absorption buffer
        uint256 totalCoveredAssets = _getJuniorTrancheEffectiveNAV().mulDiv(ConstantsLib.WAD, $.coverageWAD, Math.Rounding.Floor);
        // Compute the assets required to cover current junior tranche exposure
        uint256 jtCoverageRequired = _getJuniorTrancheRawNAV().mulDiv($.betaWAD, ConstantsLib.WAD, Math.Rounding.Ceil);
        // Compute the assets required to cover current senior tranche exposure
        uint256 stCoverageRequired = _getSeniorTrancheRawNAV();
        // Compute the amount of assets that can be deposited into senior while retaining full coverage
        return totalCoveredAssets.saturatingSub(jtCoverageRequired).saturatingSub(stCoverageRequired);
    }

    /**
     * @notice Returns the max assets withdrawable from the junior tranche without violating the market's coverage requirement
     * @dev Always rounds in favor of senior tranche protection
     * @dev Coverage Invariant: JT_EFFECTIVE_NAV >= (ST_RAW_NAV + (JT_RAW_NAV * BETA_%)) * COV_%
     * @dev Max assets withdrawable from JT, y: (JT_EFFECTIVE_NAV - y) = (ST_RAW_NAV + ((JT_RAW_NAV - y) * BETA_%)) * COV_%
     *      Isolate y: y = (JT_EFFECTIVE_NAV - (COV_% * (ST_RAW_NAV + (JT_RAW_NAV * BETA_%)))) / (1 - (BETA_% * COV_%))
     */
    function _maxJTWithdrawalGivenCoverage() internal view returns (uint256) {
        // Get the storage pointer to the base kernel state and cache beta and coverage
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();
        uint256 betaWAD = $.betaWAD;
        uint256 coverageWAD = $.coverageWAD;
        // Solve for y, rounding in favor of senior protection
        // Compute the total covered exposure of the underlying investment
        uint256 totalCoveredExposure = _getSeniorTrancheRawNAV() + _getJuniorTrancheRawNAV().mulDiv(betaWAD, ConstantsLib.WAD, Math.Rounding.Ceil);
        // Compute the minimum junior tranche assets required to cover the exposure as per the market's coverage requirement
        uint256 requiredJTAssets = totalCoveredExposure.mulDiv(coverageWAD, ConstantsLib.WAD, Math.Rounding.Ceil);
        // Compute the surplus coverage currently provided by the junior tranche based on its currently remaining loss-absorption buffer
        uint256 surplusJTAssets = _getJuniorTrancheEffectiveNAV().saturatingSub(requiredJTAssets);
        // Compute how much coverage the system retains per 1 unit of JT assets withdrawn scaled by WAD
        uint256 coverageRetentionWAD = ConstantsLib.WAD - betaWAD.mulDiv(coverageWAD, ConstantsLib.WAD, Math.Rounding.Floor);
        // Return how much of the surplus can be withdrawn while satisfying the coverage requirement
        return surplusJTAssets.mulDiv(ConstantsLib.WAD, coverageRetentionWAD, Math.Rounding.Floor);
    }

    function _computeFractionOfTotalAssetsAllocatedWAD(uint256 _assets, uint256 _totalAssets) internal pure returns (uint256) {
        return _assets.mulDiv(ConstantsLib.WAD, _totalAssets + 1, Math.Rounding.Floor);
    }

    /// @notice Returns the effective net asset value of the senior tranche
    /// @dev Includes applied coverage, ST yield distribution, and uncovered losses
    function _getSeniorTrancheEffectiveNAV() internal view returns (uint256 stEffectiveNAV) {
        (,, stEffectiveNAV,,,,) = _previewEffectiveNAVs(_previewJTYieldShareAccrual());
    }

    /// @notice Returns the effective net asset value of the junior tranche
    /// @dev Includes provided coverage, JT yield, ST yield distribution, and JT losses
    function _getJuniorTrancheEffectiveNAV() internal view returns (uint256 jtEffectiveNAV) {
        (,,, jtEffectiveNAV,,,) = _previewEffectiveNAVs(_previewJTYieldShareAccrual());
    }

    /**
     * @notice Computes raw NAV deltas for a tranche
     * @param _currentRawNAV The current raw NAV
     * @param _lastRawNAV The last recorded raw NAV
     * @return deltaNAV The delta between the last recorded and current raw NAV
     */
    function _computeRawNAVDelta(uint256 _currentRawNAV, uint256 _lastRawNAV) internal pure returns (int256 deltaNAV) {
        deltaNAV = int256(_currentRawNAV) - int256(_lastRawNAV);
    }

    /// @notice Returns the raw net asset value of the senior tranche
    /// @dev The pure net asset value of the senior tranche invested assets
    function _getSeniorTrancheRawNAV() internal view virtual returns (uint256);

    /// @notice Returns the raw net asset value of the junior tranche
    /// @dev The pure net asset value of the junior tranche invested assets
    function _getJuniorTrancheRawNAV() internal view virtual returns (uint256);

    /**
     * @notice Returns the maximum amount of assets that can be deposited into the senior tranche globally
     * @dev Implementation should consider protocol-wide limits and liquidity constraints
     * @param _receiver The receiver of the shares for the assets being deposited (used to enforce white/black lists)
     */
    function _maxSTDepositGlobally(address _receiver) internal view virtual returns (uint256);

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn from the senior tranche globally
     * @dev Implementation should consider protocol-wide limits and liquidity constraints
     * @param _owner The owner of the assets being withdrawn (used to enforce white/black lists)
     */
    function _maxSTWithdrawalGlobally(address _owner) internal view virtual returns (uint256);

    /**
     * @notice Returns the maximum amount of assets that can be deposited into the junior tranche globally
     * @dev Implementation should consider protocol-wide limits and liquidity constraints
     * @param _receiver The receiver of the shares for the assets being deposited (used to enforce white/black lists)
     */
    function _maxJTDepositGlobally(address _receiver) internal view virtual returns (uint256);

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn from the junior tranche globally
     * @dev Implementation should consider protocol-wide limits and liquidity constraints
     * @param _owner The owner of the assets being withdrawn (used to enforce white/black lists)
     */
    function _maxJTWithdrawalGlobally(address _owner) internal view virtual returns (uint256);

    /**
     * @notice Covers senior tranche losses from the junior tranche's controlled assets
     * @param _asset The asset to cover losses in
     * @param _coverageAssets The assets provided by JT to ST as loss coverage
     * @param _receiver The receiver of the coverage assets
     */
    function _coverSTLossesFromJT(address _asset, uint256 _coverageAssets, address _receiver) internal virtual;

    /**
     * @notice Claims junior tranche yield from the senior tranche's controlled assets
     * @param _asset The asset to claim yield in
     * @param _yieldAssets The assets to claim as yield
     * @param _receiver The receiver of the yield assets
     */
    function _claimJTYieldFromST(address _asset, uint256 _yieldAssets, address _receiver) internal virtual;

    /// @inheritdoc UUPSUpgradeable
    /// @dev Will revert if the caller is not the upgrader role
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(RoycoRoles.UPGRADER_ROLE) { }
}
