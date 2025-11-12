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

    /// @dev The slope when the market's utilization is less than the target utilization (scaled by WAD)
    uint256 public constant SLOPE_LT_TARGET_UTIL = 0.25e18;

    /// @dev The slope when the market's utilization is greater than or equal to the target utilization (scaled by WAD)
    uint256 public constant SLOPE_GTE_TARGET_UTIL = 7.75e18;

    /// @dev The base rate paid to the junior tranche when the utilization is exactly at the target
    uint256 public constant BASE_RATE_GTE_TARGET_UTIL = 0.225e18;

    /// @inheritdoc IRDM
    function getRewardDistribution(
        bytes32,
        uint256 _stPrincipalAmount,
        uint256 _jtCommitmentAmount,
        uint256 _expectedLossWAD
    )
        external
        pure
        returns (uint256)
    {
        /**
         * Reward Distribution Model (piecewise curve):
         *
         *   R(U) = 0.25 * U                   if U < 0.9
         *        = 7.75 * (U - 0.9) + 0.225   if U ≥ 0.9
         *
         * U ∈ [0, 1] → Utilization = (senior tranche principal * expected loss percentage) / junior tranche commitments
         * R(U)       → Reward percentage paid to the junior tranche
         *
         * Below 90% utilization, rate rises slowly (0.25 slope).
         * Above 90%, rate rises sharply (7.75 slope) to penalize high utilization and incentivize additional junior commitments.
         */

        // If any of these quantities is 0, the utilization is effectively 0, so the JT's percentage of rewards is 0%
        if (_stPrincipalAmount == 0 || _jtCommitmentAmount == 0 || _expectedLossWAD == 0) return 0;

        // Compute the utilization of the market
        // NOTE: _stPrincipalAmount and _jtCommitmentAmount are denominated in the same asset
        uint256 utilization = _stPrincipalAmount.mulDiv(_expectedLossWAD, _jtCommitmentAmount, Math.Rounding.Floor);

        // Theoretically, this branch should never be hit for the greater than case, as it would imply a violation of the
        // invariant: junior tranche commitments >= (senior tranche principal * expected loss percentage)
        if (utilization >= ConstantsLib.WAD) {
            return ConstantsLib.WAD;
        }

        // If utilization is below the kink (target), apply the first leg of R(U)
        if (utilization < ConstantsLib.TARGET_UTILIZATION) {
            return SLOPE_LT_TARGET_UTIL.mulDiv(utilization, ConstantsLib.WAD, Math.Rounding.Floor);
        } else {
            // If utilization is at or above the kink (target), apply the second leg of R(U)
            return
                SLOPE_GTE_TARGET_UTIL.mulDiv((utilization - ConstantsLib.TARGET_UTILIZATION), ConstantsLib.WAD, Math.Rounding.Floor) + BASE_RATE_GTE_TARGET_UTIL;
        }
    }
}
