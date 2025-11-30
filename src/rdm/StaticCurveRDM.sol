// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IRDM } from "../interfaces/IRDM.sol";

import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { ConstantsLib } from "../libraries/ConstantsLib.sol";

/**
 * @title StaticCurveRDM
 * @notice Royco's static curve reward distribution model (RDM)
 * @dev Responsible for computing the reward distribution between the senior and junior tranches of a Royco market
 * @dev The curve is defined as piece-wise function parameterized by the utilization of a Royco market
 */
contract StaticCurveRDM is IRDM {
    using Math for uint256;

    /**
     * @dev Constant for the target utilization of the junior tranche (90%)
     * @dev Utilization = ((ST_NAV + JT_NAV) * COV_%) / JT_NAV
     * @dev Coverage Condition: JT_NAV >= (JT_NAV + ST_NAV) * COV_%
     * @dev The above attempts to keep utilization ∈ [0,1]
     * @dev However, utilization can be greater than 1 if JT experiences a loss proportionally greater than ST
     */
    uint256 public constant TARGET_UTILIZATION = 0.9e18;

    /// @dev The slope when the market's utilization is less than the target utilization (scaled by WAD)
    uint256 public constant SLOPE_LT_TARGET_UTIL = 0.25e18;

    /// @dev The slope when the market's utilization is greater than or equal to the target utilization (scaled by WAD)
    uint256 public constant SLOPE_GTE_TARGET_UTIL = 7.75e18;

    /// @dev The base rate paid to the junior tranche when the utilization is exactly at the target
    uint256 public constant BASE_RATE_GTE_TARGET_UTIL = 0.225e18;

    /// @inheritdoc IRDM
    function getRewardDistribution(bytes32, uint256 _stTotalAssets, uint256 _jtTotalAssets, uint256 _coverageWAD) external pure returns (uint256) {
        /**
         * Reward Distribution Model (piecewise curve):
         *
         *   R(U) = 0.25 * U                   if U < 0.9
         *        = 7.75 * (U - 0.9) + 0.225   if U ≥ 0.9
         *        = 1                          if U ≥ 1
         *
         * U    → Utilization = ((ST_NAV + JT_NAV) * COV_%) / JT_NAV
         * R(U) → Percentage of ST yield paid to the junior tranche
         *
         * Below 90% utilization, JT yield allocation rises slowly (0.25 slope).
         * Above 90% utilization, JT yield allocation rises sharply (7.75 slope), penalizing high utilization and incentivizing additional junior deposits or senior withdrawals.
         */

        // If any of these quantities is 0, the utilization is effectively 0, so the JT's percentage of ST yield is 0%
        if (_stTotalAssets == 0 || _jtTotalAssets == 0 || _coverageWAD == 0) return 0;

        // Compute the utilization of the market
        // Round in favor the senior tranche
        uint256 utilization = (_stTotalAssets + _jtTotalAssets).mulDiv(_coverageWAD, _jtTotalAssets, Math.Rounding.Floor);

        // Compute R(U), rounding in favor the senior tranche
        if (utilization >= ConstantsLib.WAD) {
            // If utilization is greater than or equal to 1, apply the third leg of R(U)
            return ConstantsLib.WAD;
        } else if (utilization >= TARGET_UTILIZATION) {
            // If utilization is at or above the kink (target), apply the second leg of R(U)
            return SLOPE_GTE_TARGET_UTIL.mulDiv((utilization - TARGET_UTILIZATION), ConstantsLib.WAD, Math.Rounding.Floor) + BASE_RATE_GTE_TARGET_UTIL;
        } else {
            // If utilization is below the kink (target), apply the first leg of R(U)
            return SLOPE_LT_TARGET_UTIL.mulDiv(utilization, ConstantsLib.WAD, Math.Rounding.Floor);
        }
    }
}
