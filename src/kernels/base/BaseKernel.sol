// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Initializable } from "../../../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import { IRDM } from "../../interfaces/IRDM.sol";
import { IBaseKernel } from "../../interfaces/kernel/IBaseKernel.sol";
import { BaseKernelState, BaseKernelStorageLib } from "../../libraries/BaseKernelStorageLib.sol";
import { ConstantsLib, Math, UtilsLib } from "../../libraries/UtilsLib.sol";

/**
 * @title BaseKernel
 * @notice Base abstract contract for kernel implementations that provides delegate call protection
 * @dev Provides the foundational functionality for kernel contracts including delegatecall enforcement
 * @dev All kernel contracts should inherit from this base contract to ensure proper execution context
 *      and use the modifier as stipulated by the IBaseKernel interface.
 */
abstract contract BaseKernel is Initializable, IBaseKernel {
    using Math for uint256;

    /// @notice Thrown when the market's coverage requirement is unsatisfied
    error INSUFFICIENT_COVERAGE();

    /// @notice Thrown when the caller of a permissioned function isn't the market's senior tranche
    error ONLY_SENIOR_TRANCHE();

    /// @notice Thrown when the caller of a permissioned function isn't the market's junior tranche
    error ONLY_JUNIOR_TRANCHE();

    /// @dev Permissions the function to only the market's senior tranche
    /// @dev Should be placed on all ST deposit and withdraw functions
    modifier onlySeniorTranche() {
        require(msg.sender == BaseKernelStorageLib._getBaseKernelStorage().seniorTranche, ONLY_SENIOR_TRANCHE());
        _;
    }

    /// @dev Permissions the function to only the market's junior tranche
    /// @dev Should be placed on all JT deposit and withdraw functions
    modifier onlyJuniorTranche() {
        require(msg.sender == BaseKernelStorageLib._getBaseKernelStorage().juniorTranche, ONLY_JUNIOR_TRANCHE());
        _;
    }

    /**
     * @notice Synchronizes tranche NAVs before and after an operation (deposit or withdrawal).
     * @dev Should be placed on senior tranche withdrawal functions and junior tranche deposit functions since coverage doesn't need to be enforced
     * @dev Before execution: realizes unrealized PnL into effective NAVs
     * @dev After execution: applies the operation's raw NAV deltas (deposit or withdrawal) to effective NAVs
     */
    modifier syncNAVs() {
        // Sync the tranche NAVs based on the difference in current NAVs and checkpointed NAVs since the last operation
        // Any NAV updates caused by this are a result of unrealized PNL(s) in the underlying strategy
        _preOpSyncTrancheNAVs();
        _;
        // Sync the NAVs after the operation (deposit or withdrawal) has been executed
        // Any NAV updates caused by this are a result of a deposit or withdrawal
        _postOpSyncTrancheNAVs();
    }

    /**
     * @notice Synchronizes tranche NAVs before and after an operation (deposit or withdrawal).
     * @dev Should be placed on senior tranche deposit functions and junior tranche withdrawal functions since coverage needs to be enforced
     * @dev Before execution: realizes unrealized PnL into effective NAVs
     * @dev After execution: applies the operation's raw NAV deltas (deposit or withdrawal) to effective NAVs
     */
    modifier syncNAVsAndEnforceCoverage() {
        // Sync the tranche NAVs based on the difference in current NAVs and checkpointed NAVs since the last operation
        // Any NAV updates caused by this are a result of unrealized PNL(s) in the underlying strategy
        _preOpSyncTrancheNAVs();
        _;
        // Sync the NAVs after the operation (deposit or withdrawal) has been executed
        // Any NAV updates caused by this are a result of a deposit or withdrawal
        _postOpSyncTrancheNAVs();
        // Enforce that the coverage requirement of the market is satisfied
        _enforceCoverage();
    }

    /**
     * @notice Initializes the base kernel state
     * @dev Initializes any parent contracts and the base kernel state
     * @param _seniorTranche The address of the Royco senior tranche associated with this kernel
     * @param _juniorTranche The address of the Royco junior tranche associated with this kernel
     * @param _coverageWAD The coverage ratio that the senior tranche is expected to be protected by scaled by WAD
     * @param _betaWAD The junior tranche's sensitivity to the same downside stress that affects the senior tranche
     *                 For example, beta is 0 when JT is in the RFR and 1 when JT is in the same opportunity as senior
     * @param _rdm The market's Reward Distribution Model (RDM), responsible for determining the ST's yield split between ST and JT
     */
    function __BaseKernel_init(address _seniorTranche, address _juniorTranche, uint64 _coverageWAD, uint96 _betaWAD, address _rdm) internal onlyInitializing {
        __BaseKernel_init_unchained(_seniorTranche, _juniorTranche, _coverageWAD, _betaWAD, _rdm);
    }

    /**
     * @notice Initializes the base kernel state
     * @dev Initializes the base kernel state
     * @param _seniorTranche The address of the Royco senior tranche associated with this kernel
     * @param _juniorTranche The address of the Royco junior tranche associated with this kernel
     * @param _coverageWAD The coverage ratio that the senior tranche is expected to be protected by scaled by WAD
     * @param _betaWAD The junior tranche's sensitivity to the same downside stress that affects the senior tranche
     *                 For example, beta is 0 when JT is in the RFR and 1 when JT is in the same opportunity as senior
     * @param _rdm The market's Reward Distribution Model (RDM), responsible for determining the ST's yield split between ST and JT
     */
    function __BaseKernel_init_unchained(
        address _seniorTranche,
        address _juniorTranche,
        uint64 _coverageWAD,
        uint96 _betaWAD,
        address _rdm
    )
        internal
        onlyInitializing
    {
        // Initialize the base kernel state
        BaseKernelStorageLib.__BaseKernel_init(_seniorTranche, _juniorTranche, _coverageWAD, _betaWAD, _rdm);
    }

    /**
     * @notice Synchronizes the raw and effective NAVs of both tranches
     * @dev Only performs a pre-op sync because there is no operation being executed in the same function call as this sync
     * @return stRawNAV The senior tranche's raw NAV: the pure value of its investment
     * @return jtRawNAV The junior tranche's raw NAV: the pure value of its investment
     * @return stEffectiveNAV The senior tranche's effective NAV, including applied coverage, ST yield distribution, and uncovered losses
     * @return jtEffectiveNAV The junior tranche's effective NAV, including provided coverage, JT yield, ST yield distribution, and JT losses
     */
    function syncTrancheNAVs() external returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV) {
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
        (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV, yieldDistributed) = _previewEffecitveNAVs(twJTYieldShareAccruedWAD);
        // If yield was distributed, reset the accumulator and update the last yield distribution timestamp
        if (yieldDistributed) {
            delete $.twJTYieldShareAccruedWAD;
            $.lastDistributionTimestamp = uint32(block.timestamp);
        }

        // Checkpoint the computed NAVs
        $.lastSeniorRawNAV = stRawNAV;
        $.lastJuniorRawNAV = jtRawNAV;
        $.lastSeniorEffectiveNAV = stEffectiveNAV;
        $.lastJuniorEffectiveNAV = jtEffectiveNAV;
    }

    /**
     * @notice Previews the current raw and effective NAVs of each tranche
     * @dev Computes PnL deltas in raw NAVs since the last sync and applies JT PnL, ST losses with applicable JT coverage, and ST yield distribution
     * @param _twJTYieldShareAccruedWAD The accumulated time-weighted JT yield share since the last yield distribution
     * @return stRawNAV The senior tranche's raw NAV: the pure value of its investment
     * @return jtRawNAV The junior tranche's raw NAV: the pure value of its investment
     * @return stEffectiveNAV The senior tranche's effective NAV, including applied coverage, ST yield distribution, and uncovered losses
     * @return jtEffectiveNAV The junior tranche's effective NAV, including provided coverage, JT yield, ST yield distribution, and JT losses
     * @return yieldDistributed Boolean indicating whether the ST accrued yield and it was distributed between ST and JT
     */
    function _previewEffecitveNAVs(uint256 _twJTYieldShareAccruedWAD)
        internal
        view
        returns (uint256 stRawNAV, uint256 jtRawNAV, uint256 stEffectiveNAV, uint256 jtEffectiveNAV, bool yieldDistributed)
    {
        // Get the storage pointer to the base kernel state
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();

        // Compute the deltas in the raw NAVs of each tranche and cache the raw NAVs
        // The deltas represent the unrealized PNL(s) of the underlying investment(s) since the last NAV checkpoints
        stRawNAV = _getSeniorTrancheRawNAV();
        jtRawNAV = _getJuniorTrancheRawNAV();
        (int256 deltaST, int256 deltaJT) = _computeDeltas(stRawNAV, jtRawNAV, $.lastSeniorRawNAV, $.lastJuniorRawNAV);

        // Cache the effective NAV for each tranche as their last recorded effective NAV
        stEffectiveNAV = $.lastSeniorEffectiveNAV;
        jtEffectiveNAV = $.lastJuniorEffectiveNAV;

        // Apply the loss to the junior tranche's effective NAV
        if (deltaJT < 0) jtEffectiveNAV = Math.saturatingSub(jtEffectiveNAV, uint256(-deltaJT));
        // Junior tranche always keeps all of its appreciation
        else if (deltaJT > 0) jtEffectiveNAV += uint256(deltaJT);

        if (deltaST == 0) {
            // Senior tranche NAV experienced no change
            return (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV, false);
        } else if (deltaST < 0) {
            // Senior tranche incurred a loss
            // Apply the loss to the senior tranche's effective NAV
            uint256 loss = uint256(-deltaST);
            stEffectiveNAV = Math.saturatingSub(stEffectiveNAV, loss);
            // Compute and apply the coverage provided by the junior tranche to the senior tranche
            uint256 coverage = Math.min(loss, jtEffectiveNAV);
            stEffectiveNAV += coverage;
            jtEffectiveNAV -= coverage;
        } else {
            // Senior tranche accrued yield
            // Compute the time weighted average JT share of yield
            uint256 elapsed = block.timestamp - $.lastDistributionTimestamp;
            // Preemptively return if last yield distribution was in the same block
            if (elapsed == 0) return (stRawNAV, jtRawNAV, stEffectiveNAV, jtEffectiveNAV, false);
            uint256 jtYieldShareWAD = _twJTYieldShareAccruedWAD / elapsed;
            // Apply the yield split: adding each tranche's share of earnings to their effective NAVs
            uint256 yield = uint256(deltaST);
            uint256 jtYield = yield.mulDiv(jtYieldShareWAD, ConstantsLib.WAD, Math.Rounding.Floor);
            jtEffectiveNAV += jtYield;
            stEffectiveNAV += (yield - jtYield);
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
        uint256 jtYieldShareWAD = IRDM($.rdm).getJTYieldShare($.lastSeniorRawNAV, $.lastJuniorRawNAV, $.betaWAD, $.coverageWAD, $.lastJuniorEffectiveNAV);
        // Apply the accural of JT yield share to the accumulator, weighted by the time elapsed
        return ($.twJTYieldShareAccruedWAD + uint192(jtYieldShareWAD * elapsed));
    }

    /**
     * @notice Applies post-operation (deposit and withdrawal) raw NAV deltas to effective NAV checkpoints
     * @dev Interprets deltas strictly as deposits/withdrawals with no yield or coverage logic
     */
    function _postOpSyncTrancheNAVs() internal {
        // Get the storage pointer to the base kernel state
        BaseKernelState storage $ = BaseKernelStorageLib._getBaseKernelStorage();

        // Compute the deltas in the raw NAVs of each tranche after an operation's execution and cache the raw NAVs
        // The deltas represent the NAV changes after a deposit and withdrawal
        uint256 stRawNAV = _getSeniorTrancheRawNAV();
        uint256 jtRawNAV = _getJuniorTrancheRawNAV();
        (int256 deltaST, int256 deltaJT) = _computeDeltas(stRawNAV, jtRawNAV, $.lastSeniorRawNAV, $.lastJuniorRawNAV);
        // Update the post-operation raw NAV checkpoints
        $.lastSeniorRawNAV = stRawNAV;
        $.lastJuniorRawNAV = jtRawNAV;

        // Apply the withdrawal to the senior tranche's effective NAV
        if (deltaST < 0) $.lastSeniorEffectiveNAV = Math.saturatingSub($.lastSeniorEffectiveNAV, uint256(-deltaST));
        // Apply the deposit to the senior tranche's effective NAV
        else if (deltaST > 0) $.lastSeniorEffectiveNAV += uint256(deltaST);

        // Apply the withdrawal to the junior tranche's effective NAV
        if (deltaJT < 0) $.lastJuniorEffectiveNAV = Math.saturatingSub($.lastJuniorEffectiveNAV, uint256(-deltaJT));
        // Apply the deposit to the junior tranche's effective NAV
        else if (deltaJT > 0) $.lastJuniorEffectiveNAV += uint256(deltaJT);
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
        uint256 utilization = UtilsLib.computeUtilization($.lastSeniorRawNAV, $.lastJuniorRawNAV, $.betaWAD, $.coverageWAD, $.lastJuniorEffectiveNAV);
        require(ConstantsLib.WAD >= utilization, INSUFFICIENT_COVERAGE());
    }

    /**
     * @notice Computes raw NAV deltas for both tranches
     * @param _stCurrentRawNAV The current senior raw NAV
     * @param _jtCurrentRawNAV The current junior raw NAV
     * @param _stLastRawNAV The last senior raw NAV
     * @param _jtLastRawNAV The last junior raw NAV
     * @return deltaST The delta in last to current senior raw NAV
     * @return deltaJT The delta in last to current junior raw NAV
     */
    function _computeDeltas(
        uint256 _stCurrentRawNAV,
        uint256 _jtCurrentRawNAV,
        uint256 _stLastRawNAV,
        uint256 _jtLastRawNAV
    )
        internal
        pure
        returns (int256 deltaST, int256 deltaJT)
    {
        deltaST = int256(_stCurrentRawNAV) - int256(_stLastRawNAV);
        deltaJT = int256(_jtCurrentRawNAV) - int256(_jtLastRawNAV);
    }

    /// @notice Returns the raw net asset value of the senior tranche
    /// @dev The pure net asset value of the junior tranche invested assets
    function _getSeniorTrancheRawNAV() internal view virtual returns (uint256);

    /// @notice Returns the raw net asset value of the junior tranche
    /// @dev The pure net asset value of the junior tranche invested assets
    function _getJuniorTrancheRawNAV() internal view virtual returns (uint256);

    /// @notice Returns the effective net asset value of the senior tranche
    /// @dev Includes applied coverage, ST yield distribution, and uncovered losses
    function _getSeniorTrancheEffectiveNAV() internal view virtual returns (uint256);

    /// @notice Returns the effective net asset value of the junior tranche
    /// @dev Includes provided coverage, JT yield, ST yield distribution, and JT losses
    function _getJuniorTrancheEffectiveNAV() internal view virtual returns (uint256);
}
